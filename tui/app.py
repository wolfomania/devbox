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
CURSOR_COLUMN = 1
MARK_COLUMN = 3
# One cell of gutter after the checkbox.
NAME_START = MARK_COLUMN + glyphs.MARKER_WIDTH + 1
NAME_COLUMN = 18
STATUS_COLUMN = 26
MB_PER_GB = 1024

PAIR_DEFAULT = 0
PAIR_TITLE = 1
PAIR_CURSOR = 2
PAIR_INSTALLED = 3
PAIR_DIM = 4
PAIR_BLOCKED = 5
PAIR_SELECTED = 6

# How long to wait for the rest of an escape sequence before calling it a bare
# ESC. Long enough to survive a laggy link, short enough to feel instant.
ESC_WINDOW_MS = 150
# Longest sequence in ESC_SEQUENCES, used to stop reading runaway input.
ESC_MAX_BODY = 4

KEY_ESCAPE = 27
# Returned for input that was understood well enough to know it is not a key
# this screen acts on. Distinct from -1, which means nothing arrived.
KEY_IGNORE = -2

# Escape sequences as terminals actually send them.
#
# keypad(True) asks ncurses to decode these itself, and on a terminal that
# honours smkx it does: the arrow keys arrive as KEY_UP and friends. A
# terminal left in normal cursor mode sends CSI forms that the xterm terminfo
# entry does not list, so ncurses hands back a bare ESC followed by the
# remaining bytes. Read as a bare ESC that used to quit the screen on the
# first arrow press, which left the selection stuck on its defaults. Decode
# both forms here rather than trusting the terminal to be in the right mode.
ESC_SEQUENCES = {
    "[A": curses.KEY_UP, "OA": curses.KEY_UP,
    "[B": curses.KEY_DOWN, "OB": curses.KEY_DOWN,
    "[C": curses.KEY_RIGHT, "OC": curses.KEY_RIGHT,
    "[D": curses.KEY_LEFT, "OD": curses.KEY_LEFT,
    "[H": curses.KEY_HOME, "OH": curses.KEY_HOME, "[1~": curses.KEY_HOME,
    "[F": curses.KEY_END, "OF": curses.KEY_END, "[4~": curses.KEY_END,
    "[5~": curses.KEY_PPAGE,
    "[6~": curses.KEY_NPAGE,
}


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
        """Tick or untick one module.

        A module that is already installed cannot be ticked: it is filtered
        out of the install list either way, so a tick beside it would promise
        work that never happens.
        """
        module = self.catalogue.by_id(module_id)
        state = self.states[module_id]
        if not state.available or module.required:
            return
        if state.status == manifest_mod.STATUS_INSTALLED:
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

    def pending_ids(self):
        """The ticked modules that an install would actually act on."""
        return [
            module.id
            for module in self.catalogue.modules
            if module.id in self.selected
            and self.states[module.id].status != manifest_mod.STATUS_INSTALLED
        ]

    def pending_size(self):
        return sum(self.catalogue.by_id(i).size_mb for i in self.pending_ids())

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

    def hidden_counts(self, list_height):
        """Module rows scrolled off the top and off the bottom."""
        above = sum(1 for row in self.rows[: self.top] if row.kind == "module")
        below = sum(1 for row in self.rows[self.top + list_height:] if row.kind == "module")
        return above, below

    def draw_scroll_hint(self, win, y, width, count, glyph_name):
        """Write "N more" over the right end of a rule line.

        The list is routinely taller than the terminal, and a list that gives
        no sign of continuing reads as the whole catalogue.
        """
        if count <= 0:
            return
        hint = " %s %d more " % (self.glyph[glyph_name], count)
        column = width - 2 - len(hint)
        if column > 1:
            win.addnstr(y, column, hint, len(hint), curses.color_pair(PAIR_TITLE))

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
            win.addnstr(y, CURSOR_COLUMN, self.glyph["cursor"], 1, curses.color_pair(PAIR_CURSOR) | curses.A_BOLD)
        win.addnstr(y, MARK_COLUMN, mark, glyphs.MARKER_WIDTH, curses.color_pair(mark_pair) | curses.A_BOLD)

        # Every field is padded to its full width and written as literal cells,
        # so column alignment never depends on what the terminal left behind.
        name_attr = curses.A_BOLD if is_cursor else curses.A_NORMAL
        win.addnstr(y, NAME_START, fit(module.name, NAME_COLUMN), NAME_COLUMN, name_attr)

        column = NAME_START + NAME_COLUMN
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
        """Say what Enter will do, in the words the boxes use.

        The screen is a checklist: Space ticks a row, Enter installs every
        ticked row. People read the cursor as the selection and press Enter on
        the row they want, so the footer names the number of ticks instead.
        """
        pending = self.pending_ids()
        summary = "enter installs the %d ticked %s %s to download" % (
            len(pending),
            self.glyph["dot"],
            human_size(self.pending_size()),
        )
        if not pending:
            summary = "nothing ticked %s space ticks the row under the cursor" % self.glyph["dot"]

        keys = "up/down move  space tick  a all  n none  d reset  enter install  q quit"
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
        above, below = self.hidden_counts(list_height)
        self.draw_scroll_hint(win, 2, width, above, "more_up")
        self.draw_scroll_hint(win, height - 3, width, below, "more_down")
        win.refresh()

    # -- main loop ----------------------------------------------------------

    def toggle_cursor_row(self):
        row = self.rows[self.cursor]
        if row.kind == "module":
            self.toggle(row.module.id)

    def jump(self, to_end, height):
        indices = [i for i, row in enumerate(self.rows) if row.kind == "module"]
        if not indices:
            return
        self.cursor = indices[-1] if to_end else indices[0]
        self._scroll_into_view(height)

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
        elif key in (curses.KEY_HOME, ord("g")):
            self.jump(False, list_height)
        elif key in (curses.KEY_END, ord("G")):
            self.jump(True, list_height)
        elif key in (ord(" "), curses.KEY_RIGHT, curses.KEY_LEFT):
            self.toggle_cursor_row()
        elif key in (ord("a"), ord("A")):
            self.set_all(True)
        elif key in (ord("n"), ord("N")):
            self.set_all(False)
        elif key in (ord("d"), ord("D")):
            self.reset_defaults()
        elif key == curses.KEY_MOUSE:
            self.handle_mouse(list_height)
        elif key in (curses.KEY_ENTER, 10, 13):
            self.confirmed = True
            return False
        elif key in (ord("q"), ord("Q"), KEY_ESCAPE):
            return False
        return True

    def handle_mouse(self, list_height):
        """A click on a module line moves the cursor there and toggles it."""
        try:
            _, _, row_y, _, state = curses.getmouse()
        except curses.error:
            return
        index = self.top + row_y - HEADER_LINES
        if not 0 <= index < len(self.rows) or self.rows[index].kind != "module":
            return
        self.cursor = index
        self._scroll_into_view(list_height)
        if state & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED):
            self.toggle_cursor_row()

    # -- input --------------------------------------------------------------

    def read_key(self, win):
        """One keypress, with escape sequences decoded whatever mode the
        terminal is in. See ESC_SEQUENCES for why this is not left to curses."""
        key = win.getch()
        if key != KEY_ESCAPE:
            return key
        return self.read_escape(win)

    def read_escape(self, win):
        """Read the bytes after an ESC and name the key they spell.

        Returns the decoded key, KEY_ESCAPE when the ESC stood alone, or
        KEY_IGNORE for a sequence this screen has no use for. Only a genuinely
        solitary ESC quits, so a split or unknown sequence can never be
        mistaken for the user asking to leave.
        """
        win.timeout(ESC_WINDOW_MS)
        try:
            body = ""
            while len(body) < ESC_MAX_BODY:
                following = win.getch()
                if following < 0 or following > 255:
                    break
                body += chr(following)
                if body in ESC_SEQUENCES:
                    return ESC_SEQUENCES[body]
                if not any(known.startswith(body) for known in ESC_SEQUENCES):
                    return KEY_IGNORE
            return KEY_ESCAPE if not body else KEY_IGNORE
        finally:
            win.timeout(-1)

    def run(self, win):
        curses.curs_set(0)
        win.keypad(True)
        # Escape is also the first byte of every arrow-key sequence, so curses
        # waits before deciding. The default wait is a full second, which reads
        # as a frozen screen; 25ms is still ample to collect the rest.
        if hasattr(curses, "set_escdelay"):
            curses.set_escdelay(25)
        # Clicking a line is the other thing people try when the keys look
        # unresponsive. Terminals that report no mouse simply never send one.
        try:
            curses.mousemask(curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED)
        except curses.error:
            pass
        running = True
        while running:
            self.draw(win)
            height, _ = win.getmaxyx()
            list_height = max(1, height - HEADER_LINES - FOOTER_LINES)
            try:
                key = self.read_key(win)
            except KeyboardInterrupt:
                return
            if key in (curses.KEY_RESIZE, KEY_IGNORE, -1):
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

    # 2 means the user chose to leave, which is not a failure. install.sh
    # reserves 1 for the screen genuinely going wrong.
    if not screen.confirmed:
        return 2

    ordered = manifest_mod.resolve_order(catalogue, screen.pending_ids())
    with open(args.out, "w", encoding="utf-8") as handle:
        for module_id in ordered:
            handle.write(module_id + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
