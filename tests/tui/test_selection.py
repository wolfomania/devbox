"""What the selection screen must do, checked through a real pty.

The bug these were written for: on a terminal in normal cursor mode the arrow
keys arrive as a bare ESC followed by their remaining bytes, the screen read
that ESC as "quit", and so no key ever reached a module. Whatever the user
pressed, the selection stayed on its preselected defaults.
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import drive


# What the screen ticks on a box where nothing is installed yet: the build
# essentials and nothing else. Everything else is one keypress away, and
# deselecting seven rows every time was the cost of the old default.
#
# Swap is ticked too, and comes first, because the probe reports it as missing
# only on a box that is short of memory. On a roomy box it reads as satisfied
# and drops out of the list by itself.
DEFAULTS = ["swap", "base", "git"]


class SelectionScreenTest(unittest.TestCase):
    def state_with(self, installed):
        path = os.path.join(tempfile.mkdtemp(prefix="devbox-state-"), "state.tsv")
        return drive.write_state(path, installed)

    def starts_ticked(self, module_id):
        """Whether a module is ticked before any key is pressed.

        Mirrors the rule Screen.initial_selection applies -- default or
        required, and nothing here is installed or blocked -- so a paging
        test can tell a SPACE that toggled the row it expected apart from one
        that toggled some other row which happened to already carry the tick
        it was looking for."""
        module = drive.catalogue().by_id(module_id)
        return module.default or module.required

    def assert_landed_on(self, module_id, result):
        """SPACE toggled this row: present if it started unticked, absent if
        it started ticked. Checking plain membership would be wrong whenever
        the landing row happens to be a default -- SPACE would untick it, and
        a bare assertIn would misread that as the cursor never arriving."""
        if self.starts_ticked(module_id):
            self.assertNotIn(module_id, result.selection)
        else:
            self.assertIn(module_id, result.selection)

    # -- the defaults -------------------------------------------------------

    def test_enter_alone_installs_the_preselected_defaults(self):
        result = drive.run(["ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertEqual(result.selection, DEFAULTS)

    def test_a_module_already_installed_is_left_out(self):
        """Even ticked explicitly: `a` selects everything the box can take."""
        result = drive.run(["a", "ENTER", "y"], state=self.state_with(["go", "rust"]))
        self.assertTrue(result.confirmed)
        self.assertNotIn("go", result.selection)
        self.assertNotIn("rust", result.selection)

    # -- navigation ---------------------------------------------------------

    def test_csi_arrow_keys_move_the_cursor_instead_of_quitting(self):
        """The regression. ESC [ B is what a terminal in normal cursor mode
        sends, and it used to close the screen on the first press."""
        result = drive.run(drive.steps_to("docker") + ["SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed, "the screen quit on an arrow key")
        self.assertIn("docker", result.selection)

    def test_ss3_arrow_keys_move_the_cursor(self):
        """ESC O B, the form a terminal in application cursor mode sends."""
        steps = ["SS3_DOWN"] * len(drive.steps_to("java"))
        result = drive.run(steps + ["SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn("java", result.selection)

    def test_the_end_key_reaches_the_last_module(self):
        """The catalogue is taller than an 80x24 terminal, so the last entries
        are only reachable by scrolling. Read the last module off the live
        catalogue rather than naming one: which module ends up last changes
        whenever a manifest is added or reordered."""
        last = drive.catalogue().modules[-1].id
        result = drive.run(["END", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn(last, result.selection)

    def test_page_down_moves_past_the_fold(self):
        """One PGDN moves the cursor a whole page (drive.page_size() module
        rows), not one row at a time, so it has to land on a row that was
        below the fold on the first screen. The catalogue has already grown
        once since this test was written (18 modules to 31), which moved the
        module that used to sit at this landing spot; compute the landing
        spot instead of naming a module."""
        ids = [m.id for m in drive.catalogue().modules]
        landing = ids[min(drive.page_size(), len(ids) - 1)]
        result = drive.run(["PGDN", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assert_landed_on(landing, result)

    def test_page_up_moves_back_toward_the_top(self):
        """From the last module, one page up moves back a whole page too --
        it only runs out of list and stops on the first module if the
        catalogue is short enough for one page to reach past the top.
        Compute where a page back from the end lands instead of assuming
        it is the first row, and instead of assuming that row starts
        unticked: on a short catalogue PGUP clamps to row 0, which is
        `swap`, one of the rows the screen ticks by default."""
        ids = [m.id for m in drive.catalogue().modules]
        landing = ids[max(0, len(ids) - 1 - drive.page_size())]
        result = drive.run(["END", "PGUP", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assert_landed_on(landing, result)

    def test_right_moves_to_the_next_column(self):
        """The catalogue is laid out in columns now, so left and right move
        between them. Which module sits at the top of the second column
        depends on the catalogue, so read it off the layout."""
        landing = drive.layout().nearest(1, 0)
        module_id = drive.catalogue().modules[landing].id
        result = drive.run(["RIGHT", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assert_landed_on(module_id, result)

    def test_left_comes_back_to_the_column_it_left(self):
        first = drive.catalogue().modules[0].id
        result = drive.run(["RIGHT", "LEFT", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assert_landed_on(first, result)

    def test_the_screen_says_how_many_modules_are_out_of_view(self):
        result = drive.run(["q"])
        self.assertIn("more", result.screen)

    # -- what the screen says -----------------------------------------------

    def test_every_module_row_is_drawn_as_a_checkbox(self):
        """The screen is a checklist, and it has to look like one: people who
        read the cursor as the selection press Enter on the wrong row."""
        result = drive.run(["q"])
        self.assertIn("[x]", result.screen)
        self.assertIn("[ ]", result.screen)

    def test_the_header_says_how_many_ticked_rows_enter_installs(self):
        """It sits under the machine line, at the top: the footer of a full
        screen is where this went unread."""
        result = drive.run(["q"])
        self.assertIn("enter installs the %d ticked" % len(DEFAULTS), result.screen)

    def test_the_grid_leaves_the_descriptions_to_the_confirmation(self):
        """The grid shows names and versions, which is what lets it show the
        whole catalogue at once. The description is on the page that asks for
        a yes, where there is room for it and where it is read before
        anything is installed."""
        listing = drive.run(["q"])
        self.assertNotIn("gcc, make, curl", listing.screen)
        confirmation = drive.run(["ENTER", "n", "q"])
        self.assertIn("gcc, make, curl", confirmation.screen)

    # -- toggling -----------------------------------------------------------

    def test_space_turns_a_selected_module_off(self):
        """Twice on the same row leaves it as it was found: off."""
        result = drive.run(drive.steps_to("go") + ["SPACE", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertNotIn("go", result.selection)

    def test_an_installed_module_cannot_be_ticked(self):
        """A tick beside it would promise an install that never happens: the
        install list drops anything already installed."""
        result = drive.run(drive.steps_to("go") + ["SPACE", "ENTER", "y"], state=self.state_with(["go"]))
        self.assertNotIn("go", result.selection)

    def test_a_required_module_cannot_be_turned_off(self):
        result = drive.run(drive.steps_to("base") + ["SPACE", "ENTER", "y"])
        self.assertIn("base", result.selection)

    def test_n_clears_everything_except_the_required_modules(self):
        result = drive.run(["n", "ENTER", "y"])
        self.assertEqual(result.selection, ["base", "git"])

    # -- swap ---------------------------------------------------------------

    def test_swap_is_the_first_row_and_ticked(self):
        """It has to be first: a box short of memory needs the swapfile before
        the toolchains that would otherwise run out of it."""
        self.assertEqual(drive.catalogue().modules[0].id, "swap")
        result = drive.run(["ENTER", "y"])
        self.assertEqual(result.selection[0], "swap")

    def test_swap_drops_out_when_the_box_has_memory_enough(self):
        """The probe answers the question, so a roomy box never sees the row
        ticked and never runs the module."""
        result = drive.run(["ENTER", "y"], state=self.state_with(["swap"]))
        self.assertNotIn("swap", result.selection)

    def test_swap_can_be_turned_off(self):
        result = drive.run(drive.steps_to("swap") + ["SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertNotIn("swap", result.selection)

    def test_a_selects_every_available_module(self):
        result = drive.run(["a", "ENTER", "y"])
        expected = [m.id for m in drive.catalogue().modules]
        self.assertEqual(sorted(result.selection), sorted(expected))

    def test_d_restores_the_defaults_after_clearing(self):
        result = drive.run(["n", "d", "ENTER", "y"])
        self.assertEqual(result.selection, DEFAULTS)

    def test_a_module_needing_root_cannot_be_selected_without_root(self):
        result = drive.run(["a", "ENTER", "y"], can_root=0)
        self.assertNotIn("docker", result.selection)
        self.assertIn("go", result.selection)

    # -- confirming ---------------------------------------------------------

    def test_enter_asks_before_anything_is_installed(self):
        """Enter opens the install list for a yes; n sends it back to the
        menu with nothing written."""
        result = drive.run(["ENTER", "n", "q"])
        self.assertTrue(result.quit)
        self.assertEqual(result.selection, [])

    def test_the_confirmation_spells_out_the_install_list(self):
        result = drive.run(["ENTER", "n", "q"])
        self.assertIn("Install these %d modules" % len(DEFAULTS), result.screen)
        self.assertIn("Build essentials", result.screen)

    def test_a_second_enter_does_not_confirm_the_install(self):
        """A newline already queued in the terminal, from a paste or an
        impatient second press, used to install the defaults unseen."""
        result = drive.run(["ENTER", "ENTER", "q"])
        self.assertTrue(result.quit)
        self.assertEqual(result.selection, [])

    def test_escape_on_the_confirmation_returns_to_the_menu(self):
        result = drive.run(["ENTER", "ESC"] + drive.steps_to("editors") + ["SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn("editors", result.selection)

    # -- dependencies -------------------------------------------------------

    def test_a_dependency_is_pulled_in_and_ordered_first(self):
        result = drive.run(["n"] + drive.steps_to("codex") + ["SPACE", "ENTER", "y"])
        self.assertIn("node", result.selection)
        self.assertLess(result.selection.index("node"), result.selection.index("codex"))

    # -- leaving ------------------------------------------------------------

    def test_a_lone_escape_quits_without_writing_a_selection(self):
        result = drive.run(["ESC"])
        self.assertTrue(result.quit)
        self.assertEqual(result.selection, [])

    def test_q_quits_without_writing_a_selection(self):
        result = drive.run(["q"])
        self.assertTrue(result.quit)
        self.assertEqual(result.selection, [])

    def test_an_unrecognised_escape_sequence_is_ignored_not_read_as_a_quit(self):
        """Shift-Tab is ESC [ Z. It means nothing here, and it must not be
        mistaken for the user pressing escape."""
        result = drive.run(["SHIFT_TAB", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertEqual(result.selection, DEFAULTS)


class ColumnLayoutTest(unittest.TestCase):
    """How the catalogue is arranged, checked as a plain function.

    The arrangement is pure -- a catalogue and a terminal size in, columns of
    cells out -- so nothing here needs a pty.
    """

    def test_the_catalogue_is_laid_out_in_more_than_one_column(self):
        self.assertGreater(len(drive.layout().columns), 1)

    def test_every_module_is_placed_exactly_once(self):
        cells = [cell
                 for column in drive.layout().columns
                 for cell in column if cell.kind == "module"]
        self.assertEqual(sorted(cell.index for cell in cells),
                         list(range(len(drive.catalogue().modules))))

    def test_a_category_keeps_its_modules_in_one_column(self):
        """A category is only ever split when it is taller than a whole
        column, and none of them is."""
        layout = drive.layout()
        columns = {}
        for index, module in enumerate(drive.catalogue().modules):
            columns.setdefault(module.category, set()).add(layout.column_of(index))
        for category, numbers in columns.items():
            self.assertEqual(len(numbers), 1, "%s is split across columns" % category)

    def test_a_narrow_terminal_falls_back_to_one_column(self):
        layout = drive.app_mod.build_layout(drive.catalogue(), 40, 20)
        self.assertEqual(layout.visible, 1)

    def test_a_wide_terminal_gets_more_columns_than_a_narrow_one(self):
        narrow = drive.app_mod.build_layout(drive.catalogue(), 80, 20)
        wide = drive.app_mod.build_layout(drive.catalogue(), 160, 20)
        self.assertGreater(wide.visible, narrow.visible)


if __name__ == "__main__":
    unittest.main(verbosity=2)
