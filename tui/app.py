"""The devbox selection screen.

Reads the module catalogue and the probe results, lets the user pick what to
install, and writes the chosen ids to a file for install.sh to act on. Nothing
is installed from here; this process only produces a selection.
"""

import argparse
import curses
import sys
from dataclasses import dataclass

import glyphs
import manifest as manifest_mod

# Layout constants, all in terminal cells.
HEADER_LINES = 3
FOOTER_LINES = 3
NAME_COLUMN = 22
STATUS_COLUMN = 26
MB_PER_GB = 1024

PAIR_DEFAULT = 0
PAIR_TITLE = 1
PAIR_CURSOR = 2
PAIR_INSTALLED = 3
PAIR_DIM = 4
PAIR_BLOCKED = 5
PAIR_SELECTED = 6


@dataclass
class Row:
    """One line in the list: either a category heading or a module."""

    kind: str
    label: str
    module: object = None


@dataclass
class ModuleState:
    """Everything the screen needs to know about one module's current status."""

    status: str
    version: str
    available: bool
    reason: str


def read_states(path, catalogue, can_root):
    """Merge probe output with availability rules into per-module state."""
    probed = {}
    if path:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    probed[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else "")

    states = {}
    for module in catalogue.modules:
        status, version = probed.get(module.id, (manifest_mod.STATUS_MISSING, ""))
        available = can_root or not module.needs_root
        reason = "" if available else "needs root"
        states[module.id] = ModuleState(status, version, available, reason)
    return states


def initial_selection(catalogue, states):
    """Preselect defaults, but never anything already installed or blocked."""
    chosen = set()
    for module in catalogue.modules:
        state = states[module.id]
        if not state.available or state.status == manifest_mod.STATUS_INSTALLED:
            continue
        if module.default or module.required:
            chosen.add(module.id)
    return chosen


def build_rows(catalogue):
    rows = []
    for category in catalogue.categories:
        rows.append(Row(kind="header", label=category.title.upper()))
        for module in catalogue.in_category(category.id):
            rows.append(Row(kind="module", label=module.name, module=module))
    return rows


def fit(text, width):
    """Pad or truncate to exactly `width` cells, leaving one cell of gutter."""
    if width <= 1:
        return " " * max(0, width)
    if len(text) > width - 1:
        return text[: width - 2] + "\u2026 "
    return text.ljust(width)


def human_size(total_mb):
    if total_mb >= MB_PER_GB:
        return "%.1f GB" % (total_mb / MB_PER_GB)
    return "%d MB" % total_mb


class Screen:
    def __init__(self, catalogue, states, machine, out_path):
        self.catalogue = catalogue
        self.states = states
        self.machine = machine
        self.out_path = out_path
        self.rows = build_rows(catalogue)
        self.selected = initial_selection(catalogue, states)
        self.glyph = glyphs.pick()
        self.cursor = self._first_module_row()
        self.top = 0
        self.confirmed = False

    # -- navigation ---------------------------------------------------------

    def _first_module_row(self):
        for index, row in enumerate(self.rows):
            if row.kind == "module":
                return index
        return 0

    def move(self, delta, height):
        index = self.cursor
        while True:
            index += delta
            if index < 0 or index >= len(self.rows):
                return
            if self.rows[index].kind == "module":
                break
        self.cursor = index
        self._scroll_into_view(height)

    def _scroll_into_view(self, height):
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + height:
            self.top = self.cursor - height + 1

    # -- selection ----------------------------------------------------------

    def toggle(self, module_id):
        module = self.catalogue.by_id(module_id)
        state = self.states[module_id]
        if not state.available or module.required:
            return
        if module_id in self.selected:
            self.selected.discard(module_id)
        else:
            self.selected.add(module_id)

    def set_all(self, value):
        for module in self.catalogue.modules:
            state = self.states[module.id]
            if not state.available:
                continue
            if value and state.status != manifest_mod.STATUS_INSTALLED:
                self.selected.add(module.id)
            elif not value and not module.required:
                self.selected.discard(module.id)

    def reset_defaults(self):
        self.selected = initial_selection(self.catalogue, self.states)

    def pending_size(self):
        return sum(self.catalogue.by_id(i).size_mb for i in self.selected)

    # -- drawing ------------------------------------------------------------

    def marker(self, module):
        state = self.states[module.id]
        if not state.available:
            return self.glyph["blocked"], PAIR_BLOCKED
        if state.status == manifest_mod.STATUS_INSTALLED and module.id not in self.selected:
            return self.glyph["installed"], PAIR_INSTALLED
        if module.id in self.selected:
            return self.glyph["checked"], PAIR_SELECTED
        return self.glyph["unchecked"], PAIR_DEFAULT

    def status_text(self, module):
        state = self.states[module.id]
        if not state.available:
            return state.reason, PAIR_BLOCKED
        if state.status == manifest_mod.STATUS_INSTALLED:
            return (state.version or "installed"), PAIR_INSTALLED
        if module.pin and module.pin not in ("apt", "latest"):
            return module.pin, PAIR_DIM
        return "", PAIR_DIM

    def draw_header(self, win, width):
        win.addnstr(0, 1, "devbox", width - 2, curses.color_pair(PAIR_TITLE) | curses.A_BOLD)
        win.addnstr(1, 1, self.machine, width - 2, curses.color_pair(PAIR_DIM))
        win.addnstr(2, 1, self.glyph["rule"] * max(0, width - 2), width - 2, curses.color_pair(PAIR_DIM))

    def draw_row(self, win, y, index, width):
        row = self.rows[index]
        if row.kind == "header":
            win.addnstr(y, 2, row.label, width - 4, curses.color_pair(PAIR_TITLE) | curses.A_BOLD)
            return

        module = row.module
        is_cursor = index == self.cursor
        mark, mark_pair = self.marker(module)
        status, status_pair = self.status_text(module)

        if is_cursor:
            win.addnstr(y, 1, self.glyph["cursor"], 1, curses.color_pair(PAIR_CURSOR) | curses.A_BOLD)
        win.addnstr(y, 3, mark, 1, curses.color_pair(mark_pair) | curses.A_BOLD)

        # Every field is padded to its full width and written as literal cells,
        # so column alignment never depends on what the terminal left behind.
        name_attr = curses.A_BOLD if is_cursor else curses.A_NORMAL
        win.addnstr(y, 5, fit(module.name, NAME_COLUMN), NAME_COLUMN, name_attr)

        column = 5 + NAME_COLUMN
        if column < width - 2:
            limit = min(STATUS_COLUMN, width - column - 2)
            win.addnstr(y, column, fit(status, limit), limit, curses.color_pair(status_pair))

        column += STATUS_COLUMN
        if column < width - 4:
            detail = module.summary
            if module.size_mb and self.states[module.id].status != manifest_mod.STATUS_INSTALLED:
                detail = "%s %s %s" % (human_size(module.size_mb), self.glyph["dot"], detail)
            win.addnstr(y, column, detail, width - column - 2, curses.color_pair(PAIR_DIM))

    def draw_footer(self, win, height, width):
        pending = [i for i in self.selected if self.states[i].status != manifest_mod.STATUS_INSTALLED]
        summary = "%d selected %s %s to download" % (
            len(self.selected),
            self.glyph["dot"],
            human_size(self.pending_size()),
        )
        if not pending:
            summary = "nothing selected %s everything ticked is already installed" % self.glyph["dot"]

        keys = "up/down move   space toggle   a all   n none   d defaults   enter install   q quit"
        win.addnstr(height - 3, 1, self.glyph["rule"] * max(0, width - 2), width - 2, curses.color_pair(PAIR_DIM))
        win.addnstr(height - 2, 1, summary, width - 2, curses.color_pair(PAIR_TITLE))
        win.addnstr(height - 1, 1, keys, width - 2, curses.color_pair(PAIR_DIM))

    def draw(self, win):
        win.erase()
        height, width = win.getmaxyx()
        list_height = max(1, height - HEADER_LINES - FOOTER_LINES)

        self.draw_header(win, width)
        self._scroll_into_view(list_height)

        for offset in range(list_height):
            index = self.top + offset
            if index >= len(self.rows):
                break
            self.draw_row(win, HEADER_LINES + offset, index, width)

        self.draw_footer(win, height, width)
        win.refresh()

    # -- main loop ----------------------------------------------------------

    def handle_key(self, key, list_height):
        if key in (curses.KEY_UP, ord("k")):
            self.move(-1, list_height)
        elif key in (curses.KEY_DOWN, ord("j")):
            self.move(1, list_height)
        elif key in (curses.KEY_PPAGE,):
            for _ in range(list_height):
                self.move(-1, list_height)
        elif key in (curses.KEY_NPAGE,):
            for _ in range(list_height):
                self.move(1, list_height)
        elif key in (ord(" "), curses.KEY_RIGHT, curses.KEY_LEFT):
            row = self.rows[self.cursor]
            if row.kind == "module":
                self.toggle(row.module.id)
        elif key in (ord("a"), ord("A")):
            self.set_all(True)
        elif key in (ord("n"), ord("N")):
            self.set_all(False)
        elif key in (ord("d"), ord("D")):
            self.reset_defaults()
        elif key in (curses.KEY_ENTER, 10, 13):
            self.confirmed = True
            return False
        elif key in (ord("q"), ord("Q"), 27):
            return False
        return True

    def run(self, win):
        curses.curs_set(0)
        win.keypad(True)
        running = True
        while running:
            self.draw(win)
            height, _ = win.getmaxyx()
            list_height = max(1, height - HEADER_LINES - FOOTER_LINES)
            try:
                key = win.getch()
            except KeyboardInterrupt:
                return
            if key == curses.KEY_RESIZE:
                continue
            running = self.handle_key(key, list_height)


def init_colors():
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(PAIR_TITLE, curses.COLOR_CYAN, -1)
    curses.init_pair(PAIR_CURSOR, curses.COLOR_CYAN, -1)
    curses.init_pair(PAIR_INSTALLED, curses.COLOR_GREEN, -1)
    curses.init_pair(PAIR_DIM, curses.COLOR_BLUE, -1)
    curses.init_pair(PAIR_BLOCKED, curses.COLOR_YELLOW, -1)
    curses.init_pair(PAIR_SELECTED, curses.COLOR_CYAN, -1)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="devbox module selection screen")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--state", default="")
    parser.add_argument("--out", required=True)
    parser.add_argument("--machine", default="")
    parser.add_argument("--can-root", type=int, default=1)
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    catalogue = manifest_mod.load(args.manifest)
    states = read_states(args.state, catalogue, bool(args.can_root))
    screen = Screen(catalogue, states, args.machine, args.out)

    def bootstrap(win):
        init_colors()
        screen.run(win)

    curses.wrapper(bootstrap)

    if not screen.confirmed:
        return 1

    pending = [i for i in screen.selected if states[i].status != manifest_mod.STATUS_INSTALLED]
    ordered = manifest_mod.resolve_order(catalogue, pending)
    with open(args.out, "w", encoding="utf-8") as handle:
        for module_id in ordered:
            handle.write(module_id + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
