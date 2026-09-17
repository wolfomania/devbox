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
#
# The header carries the name, the machine, the line that says what Enter
# would install, and a rule. That line used to sit in the footer, where the
# eye lands last and, on a full screen, often not at all; it answers the only
# question the screen exists to answer, so it goes under the machine.
HEADER_LINES = 4
# Rule and key hints.
FOOTER_LINES = 2

# One module row inside a column: the cursor, the checkbox, the name, and
# whatever version the module is pinned to or already carries.
CURSOR_OFFSET = 0
MARK_OFFSET = 2
NAME_OFFSET = MARK_OFFSET + glyphs.MARKER_WIDTH + 1
NAME_WIDTH = 20
# A column has to hold the longest name and a version beside it, and two of
# them have to fit across an 80-column terminal.
MIN_COLUMN_WIDTH = NAME_OFFSET + NAME_WIDTH + 8
MAX_COLUMN_WIDTH = 42
MAX_COLUMNS = 4

# The confirmation is a single list, not a grid: name, download size, then the
# description the grid has no room for.
CONFIRM_INDENT = 2
SIZE_WIDTH = 9
# Rule, download size and key hints under the confirmation list.
CONFIRM_FOOTER_LINES = 3

MB_PER_GB = 1024

PAIR_DEFAULT = 0
PAIR_TITLE = 1
PAIR_CURSOR = 2
PAIR_INSTALLED = 3
PAIR_DIM = 4
PAIR_BLOCKED = 5
PAIR_SELECTED = 6

# How long to wait for the rest of an escape sequence, or of a multi-byte
# character, before giving up on it. Long enough to survive a laggy link,
# short enough to feel instant.
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
class ModuleState:
    """Everything the screen needs to know about one module's current status."""

    status: str
    version: str
    available: bool
    reason: str


@dataclass(frozen=True)
class Cell:
    """One line inside a column: a category heading, a module, or a gap."""

    kind: str
    label: str = ""
    # Where the module sits in the catalogue. The cursor is this number, so
    # moving down a column and on to the top of the next is a single step.
    index: int = -1


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


def fit(text, width):
    """Pad or truncate to exactly `width` cells, leaving one cell of gutter."""
    if width <= 1:
        return " " * max(0, width)
    if len(text) > width - 1:
        return text[: width - 2] + "… "
    return text.ljust(width)


def human_size(total_mb):
    if total_mb >= MB_PER_GB:
        return "%.1f GB" % (total_mb / MB_PER_GB)
    return "%d MB" % total_mb


# -- layout -----------------------------------------------------------------


class Layout:
    """The catalogue arranged into columns, for one terminal size."""

    def __init__(self, columns, visible, width, height):
        self.columns = columns
        # Columns the terminal has room for. There can be more than this, and
        # then the screen pages sideways.
        self.visible = visible
        self.width = width
        self.height = height
        self.positions = {
            cell.index: (number, line)
            for number, column in enumerate(columns)
            for line, cell in enumerate(column)
            if cell.kind == "module"
        }

    def position(self, index):
        """Where a module sits, as (column, line)."""
        return self.positions.get(index, (0, 0))

    def column_of(self, index):
        return self.position(index)[0]

    def modules_in(self, number):
        """Catalogue positions of the modules in one column, top to bottom."""
        if not 0 <= number < len(self.columns):
            return ()
        return tuple(c.index for c in self.columns[number] if c.kind == "module")

    def nearest(self, number, line):
        """The module in this column closest to `line`, or None if it has none."""
        if not self.columns:
            return None
        number = max(0, min(number, len(self.columns) - 1))
        best = None
        for offset, cell in enumerate(self.columns[number]):
            if cell.kind != "module":
                continue
            distance = abs(offset - line)
            if best is None or distance < best[0]:
                best = (distance, cell.index)
        return best[1] if best else None

    @property
    def page(self):
        """Modules on screen at once: how far one page key moves the cursor."""
        return max(1, sum(len(self.modules_in(n)) for n in range(self.visible)))


def column_geometry(width):
    """How many columns fit across this terminal, and how wide each one is."""
    room = max(1, width - 2)
    count = max(1, min(MAX_COLUMNS, room // MIN_COLUMN_WIDTH))
    return count, min(MAX_COLUMN_WIDTH, room // count)


def build_blocks(catalogue):
    """One block per category: its heading, then its modules, in order."""
    position = {module.id: index for index, module in enumerate(catalogue.modules)}
    blocks = []
    for category in catalogue.categories:
        cells = [Cell("header", category.title.upper())]
        for module in catalogue.in_category(category.id):
            cells.append(Cell("module", module.name, position[module.id]))
        blocks.append(tuple(cells))
    return tuple(blocks)


def flow(blocks, height):
    """Pour the category blocks into columns of at most `height` lines.

    A category stays whole, in one column, with a blank line between it and
    the category above it. One too tall for a column is the only thing that
    gets split, and then only because it has to be.
    """
    columns = [[]]
    for block in blocks:
        current = columns[-1]
        if current and len(current) + 1 + len(block) > height:
            columns.append([])
        elif current:
            current.append(Cell("blank"))
        for cell in block:
            if len(columns[-1]) >= height:
                columns.append([])
            columns[-1].append(cell)
    return tuple(tuple(column) for column in columns)


def build_layout(catalogue, width, height):
    """Arrange the catalogue for a terminal of this size.

    Columns are made no taller than they need to be, so a catalogue that fits
    the screen is spread evenly across it rather than stacked into one full
    column and a stub of a second. A catalogue that does not fit runs its
    columns to the full height, and the screen pages sideways instead.
    """
    blocks = build_blocks(catalogue)
    count, column_width = column_geometry(width)
    total = sum(len(block) for block in blocks) + max(0, len(blocks) - 1)
    even = max(1, -(-total // count))

    columns = flow(blocks, height)
    for trial in range(min(even, height), height):
        candidate = flow(blocks, trial)
        if len(candidate) <= count:
            columns = candidate
            break
    return Layout(columns, count, column_width, height)


# -- input ------------------------------------------------------------------

# The Latin letter on the same physical key, for a keyboard typing another
# script. Someone who left their layout on Ukrainian presses the key marked q
# and the terminal sends й; the screen would otherwise ignore every letter
# shortcut it has, while Enter, Space, the arrows and Esc kept working, which
# reads as half the keyboard being broken. Only the keys this screen uses are
# listed. The Cyrillic letters are the ЙЦУКЕН layout, which Ukrainian and
# Russian share on these keys.
CYRILLIC_KEYS = (
    ("й", "q"), ("н", "y"), ("ф", "a"), ("в", "d"), ("п", "g"),
    ("о", "j"), ("л", "k"), ("т", "n"), ("р", "h"), ("д", "l"),
)
KEY_ALIASES = dict(
    [(letter, latin) for letter, latin in CYRILLIC_KEYS]
    + [(letter.upper(), latin.upper()) for letter, latin in CYRILLIC_KEYS]
)

# Lead byte of a UTF-8 character, and the number of bytes that follow it.
UTF8_TAILS = ((0xF0, 3), (0xE0, 2), (0xC2, 1))


def alias_key(character):
    """The key a character stands for, or KEY_IGNORE for one we have no use for."""
    latin = KEY_ALIASES.get(character)
    return ord(latin) if latin else KEY_IGNORE


class Screen:
    def __init__(self, catalogue, states, machine, out_path):
        self.catalogue = catalogue
        self.states = states
        self.machine = machine
        self.out_path = out_path
        self.modules = list(catalogue.modules)
        self.selected = initial_selection(catalogue, states)
        self.glyph = glyphs.pick()
        # The cursor is a position in the catalogue; the layout says where on
        # screen that lands.
        self.cursor = 0
        # Leftmost column on screen, and the first line of the confirmation
        # list, for the catalogues too big to show at once.
        self.left = 0
        self.confirm_top = 0
        self.confirmed = False
        self._layout = None

    # -- layout -------------------------------------------------------------

    def layout(self, win):
        """The column arrangement for the terminal as it is right now."""
        height, width = win.getmaxyx()
        list_height = max(1, height - HEADER_LINES - FOOTER_LINES)
        key = (width, list_height)
        if self._layout is None or self._layout[0] != key:
            self._layout = (key, build_layout(self.catalogue, width, list_height))
        return self._layout[1]

    # -- navigation ---------------------------------------------------------

    def move(self, delta):
        """Along the catalogue, which is also the order the columns read in:
        down a column, then on to the top of the next."""
        self.cursor = max(0, min(self.cursor + delta, len(self.modules) - 1))

    def move_column(self, delta, layout):
        number, line = layout.position(self.cursor)
        target = layout.nearest(number + delta, line)
        if target is not None:
            self.cursor = target

    def jump(self, to_end):
        self.cursor = len(self.modules) - 1 if to_end else 0

    def scroll_into_view(self, layout):
        number = layout.column_of(self.cursor)
        if number < self.left:
            self.left = number
        elif number >= self.left + layout.visible:
            self.left = number - layout.visible + 1
        last_start = max(0, len(layout.columns) - layout.visible)
        self.left = max(0, min(self.left, last_start))

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

    def toggle_cursor_row(self):
        if 0 <= self.cursor < len(self.modules):
            self.toggle(self.modules[self.cursor].id)

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

    def install_list(self):
        """Exactly what an install would run, in the order it would run it.

        Dependencies are pulled in even when they were not ticked, and
        anything already installed is dropped, which is the rule the headless
        path in install.sh applies too.
        """
        ordered = manifest_mod.resolve_order(self.catalogue, self.pending_ids())
        return [i for i in ordered if self.states[i].status != manifest_mod.STATUS_INSTALLED]

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

    def summary(self):
        """What Enter would do, in the words the boxes use.

        The screen is a checklist: Space ticks a row, Enter installs every
        ticked row. People read the cursor as the selection and press Enter
        on the row they want, so this names the number of ticks instead.
        """
        pending = self.pending_ids()
        if not pending:
            return "nothing ticked %s space ticks the row under the cursor" % self.glyph["dot"]
        return "enter installs the %d ticked %s %s to download" % (
            len(pending),
            self.glyph["dot"],
            human_size(self.pending_size()),
        )

    def draw_header(self, win, width, summary=""):
        win.addnstr(0, 1, "devbox", width - 2, curses.color_pair(PAIR_TITLE) | curses.A_BOLD)
        win.addnstr(1, 1, self.machine, width - 2, curses.color_pair(PAIR_DIM))
        if summary:
            win.addnstr(2, 1, summary, width - 2, curses.color_pair(PAIR_TITLE))
        win.addnstr(HEADER_LINES - 1, 1, self.glyph["rule"] * max(0, width - 2),
                    width - 2, curses.color_pair(PAIR_DIM))

    def draw_footer(self, win, height, width):
        keys = "arrows move  space tick  a all  n none  d reset  enter install  q quit"
        win.addnstr(height - FOOTER_LINES, 1, self.glyph["rule"] * max(0, width - 2),
                    width - 2, curses.color_pair(PAIR_DIM))
        win.addnstr(height - 1, 1, keys, width - 2, curses.color_pair(PAIR_DIM))

    def draw_module(self, win, y, x, index, column_width):
        """One module: checkbox, name, version. No description.

        The description is what made this a one-module-per-line list, and a
        one-module-per-line list is what made the catalogue three screens
        tall. It is spelled out on the confirmation instead, where there is
        room for it and where it is read before anything is installed.
        """
        module = self.modules[index]
        is_cursor = index == self.cursor
        mark, mark_pair = self.marker(module)

        if is_cursor:
            win.addnstr(y, x + CURSOR_OFFSET, self.glyph["cursor"], 1,
                        curses.color_pair(PAIR_CURSOR) | curses.A_BOLD)
        win.addnstr(y, x + MARK_OFFSET, mark, glyphs.MARKER_WIDTH,
                    curses.color_pair(mark_pair) | curses.A_BOLD)

        # Every field is padded to its full width and written as literal
        # cells, so column alignment never depends on what the terminal left
        # behind.
        name_attr = curses.A_BOLD if is_cursor else curses.A_NORMAL
        win.addnstr(y, x + NAME_OFFSET, fit(module.name, NAME_WIDTH), NAME_WIDTH, name_attr)

        status, status_pair = self.status_text(module)
        room = column_width - NAME_OFFSET - NAME_WIDTH
        if status and room > 1:
            win.addnstr(y, x + NAME_OFFSET + NAME_WIDTH, fit(status, room), room,
                        curses.color_pair(status_pair))

    def draw_grid(self, win, layout):
        for offset in range(layout.visible):
            number = self.left + offset
            if number >= len(layout.columns):
                break
            x = 1 + offset * layout.width
            for line, cell in enumerate(layout.columns[number]):
                y = HEADER_LINES + line
                if cell.kind == "header":
                    room = layout.width - MARK_OFFSET
                    win.addnstr(y, x + MARK_OFFSET, fit(cell.label, room), room,
                                curses.color_pair(PAIR_TITLE) | curses.A_BOLD)
                elif cell.kind == "module":
                    self.draw_module(win, y, x, cell.index, layout.width)

    def hidden_counts(self, layout):
        """Modules in the columns off the left and off the right of the screen."""
        before = sum(len(layout.modules_in(n)) for n in range(self.left))
        after = sum(len(layout.modules_in(n))
                    for n in range(self.left + layout.visible, len(layout.columns)))
        return before, after

    def draw_hint(self, win, y, column, text):
        if column > 1:
            win.addnstr(y, column, text, len(text), curses.color_pair(PAIR_TITLE))

    def draw_column_hints(self, win, y, width, layout):
        """Write "N more" over the ends of a rule line.

        The catalogue is routinely wider than the terminal, and a grid that
        gives no sign of continuing reads as the whole catalogue.
        """
        before, after = self.hidden_counts(layout)
        if before:
            self.draw_hint(win, y, 2, " %s %d more " % (self.glyph["more_left"], before))
        if after:
            hint = " %d more %s " % (after, self.glyph["more_right"])
            self.draw_hint(win, y, width - 2 - len(hint), hint)

    def draw(self, win):
        win.erase()
        height, width = win.getmaxyx()
        layout = self.layout(win)
        self.scroll_into_view(layout)

        self.draw_header(win, width, self.summary())
        self.draw_grid(win, layout)
        self.draw_footer(win, height, width)
        self.draw_column_hints(win, height - FOOTER_LINES, width, layout)
        win.refresh()

    # -- the confirmation ---------------------------------------------------

    def draw_confirm_row(self, win, y, width, module):
        size = human_size(module.size_mb) if module.size_mb else ""
        win.addnstr(y, CONFIRM_INDENT, fit(module.name, NAME_WIDTH), NAME_WIDTH, curses.A_BOLD)
        win.addnstr(y, CONFIRM_INDENT + NAME_WIDTH, fit(size, SIZE_WIDTH), SIZE_WIDTH,
                    curses.color_pair(PAIR_DIM))
        column = CONFIRM_INDENT + NAME_WIDTH + SIZE_WIDTH
        room = width - column - 1
        if module.summary and room > 1:
            win.addnstr(y, column, fit(module.summary, room), room,
                        curses.color_pair(PAIR_DIM))

    def draw_confirm(self, win, ids):
        """The install list, spelled out, with nothing else on the screen.

        This is where the descriptions live. The grid shows names and
        versions so that it can show the whole catalogue at once; the page
        that asks for a yes has the room to say what each module is.
        """
        win.erase()
        height, width = win.getmaxyx()
        self.draw_header(win, width, "Install these %d modules:" % len(ids))

        top = HEADER_LINES
        room = max(1, height - top - CONFIRM_FOOTER_LINES)
        self.confirm_top = max(0, min(self.confirm_top, len(ids) - room))
        for offset, module_id in enumerate(ids[self.confirm_top:self.confirm_top + room]):
            self.draw_confirm_row(win, top + offset, width, self.catalogue.by_id(module_id))

        total = sum(self.catalogue.by_id(i).size_mb for i in ids)
        keys = "y installs  any other key goes back"
        if len(ids) > room:
            keys = "y installs  up/down scrolls  any other key goes back"
        rule = height - CONFIRM_FOOTER_LINES
        win.addnstr(rule, 1, self.glyph["rule"] * max(0, width - 2), width - 2,
                    curses.color_pair(PAIR_DIM))
        if self.confirm_top:
            self.draw_hint(win, rule, 2, " %s %d more " % (self.glyph["more_up"], self.confirm_top))
        rest = len(ids) - self.confirm_top - room
        if rest > 0:
            hint = " %d more %s " % (rest, self.glyph["more_down"])
            self.draw_hint(win, rule, width - 2 - len(hint), hint)
        win.addnstr(height - 2, 1, "%s to download" % human_size(total), width - 2,
                    curses.color_pair(PAIR_TITLE))
        win.addnstr(height - 1, 1, keys, width - 2, curses.color_pair(PAIR_DIM))
        win.refresh()

    def ask_to_install(self, win):
        """Show the install list and wait for a yes. True once it has one.

        Only `y` confirms. Enter is the key a terminal is most likely to have
        queued already, from a pasted command or an impatient second press,
        and it used to install the defaults before the menu was ever read;
        here it takes the user back to the list like any other key.
        """
        ids = self.install_list()
        if not ids:
            # Nothing to install. install.sh says so; there is nothing to ask.
            self.confirmed = True
            return True
        self.confirm_top = 0
        while True:
            self.draw_confirm(win, ids)
            key = self.read_key(win)
            if key == curses.KEY_RESIZE:
                continue
            if key in (curses.KEY_UP, ord("k")):
                self.confirm_top -= 1
                continue
            if key in (curses.KEY_DOWN, ord("j")):
                self.confirm_top += 1
                continue
            if key in (ord("y"), ord("Y")):
                self.confirmed = True
                return True
            return False

    # -- main loop ----------------------------------------------------------

    def handle_key(self, key, layout):
        if key in (curses.KEY_UP, ord("k")):
            self.move(-1)
        elif key in (curses.KEY_DOWN, ord("j")):
            self.move(1)
        elif key in (curses.KEY_LEFT, ord("h")):
            self.move_column(-1, layout)
        elif key in (curses.KEY_RIGHT, ord("l")):
            self.move_column(1, layout)
        elif key == curses.KEY_PPAGE:
            self.move(-layout.page)
        elif key == curses.KEY_NPAGE:
            self.move(layout.page)
        elif key in (curses.KEY_HOME, ord("g")):
            self.jump(False)
        elif key in (curses.KEY_END, ord("G")):
            self.jump(True)
        elif key == ord(" "):
            self.toggle_cursor_row()
        elif key in (ord("a"), ord("A")):
            self.set_all(True)
        elif key in (ord("n"), ord("N")):
            self.set_all(False)
        elif key in (ord("d"), ord("D")):
            self.reset_defaults()
        elif key == curses.KEY_MOUSE:
            self.handle_mouse(layout)
        elif key in (ord("q"), ord("Q"), KEY_ESCAPE):
            return False
        return True

    def handle_mouse(self, layout):
        """A click on a module moves the cursor there and toggles it."""
        try:
            _, mouse_x, mouse_y, _, state = curses.getmouse()
        except curses.error:
            return
        line = mouse_y - HEADER_LINES
        if mouse_x < 1 or line < 0:
            return
        number = self.left + (mouse_x - 1) // layout.width
        if not 0 <= number < len(layout.columns):
            return
        column = layout.columns[number]
        if line >= len(column) or column[line].kind != "module":
            return
        self.cursor = column[line].index
        if state & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED):
            self.toggle_cursor_row()

    # -- input --------------------------------------------------------------

    def read_key(self, win):
        """One keypress, with escape sequences decoded whatever mode the
        terminal is in, and letters read whatever script they arrive in.
        See ESC_SEQUENCES for why this is not left to curses."""
        key = win.getch()
        if key == KEY_ESCAPE:
            return self.read_escape(win)
        # Above 255 is ncurses naming a key of its own, KEY_DOWN and the
        # rest; only a byte in this range is part of a character.
        if 127 < key < 256:
            return self.read_character(win, key)
        return key

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

    def read_character(self, win, lead):
        """Assemble one multi-byte character and name the key it sits on.

        curses hands UTF-8 back one byte at a time, so a Cyrillic letter
        arrives as a pair of bytes that mean nothing on their own. See
        KEY_ALIASES for why the screen bothers to read them.
        """
        tail = next((count for start, count in UTF8_TAILS if lead >= start), 0)
        if not tail:
            return KEY_IGNORE
        body = bytes([lead])
        win.timeout(ESC_WINDOW_MS)
        try:
            for _ in range(tail):
                following = win.getch()
                if not 0x80 <= following <= 0xBF:
                    return KEY_IGNORE
                body += bytes([following])
        finally:
            win.timeout(-1)
        try:
            return alias_key(body.decode("utf-8"))
        except UnicodeDecodeError:
            return KEY_IGNORE

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
            layout = self.layout(win)
            try:
                key = self.read_key(win)
            except KeyboardInterrupt:
                return
            if key in (curses.KEY_RESIZE, KEY_IGNORE, -1):
                continue
            if key in (curses.KEY_ENTER, 10, 13):
                if self.ask_to_install(win):
                    return
                continue
            running = self.handle_key(key, layout)


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

    with open(args.out, "w", encoding="utf-8") as handle:
        for module_id in screen.install_list():
            handle.write(module_id + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
