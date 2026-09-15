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
DEFAULTS = ["base", "git"]


class SelectionScreenTest(unittest.TestCase):
    def state_with(self, installed):
        path = os.path.join(tempfile.mkdtemp(prefix="devbox-state-"), "state.tsv")
        return drive.write_state(path, installed)

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
        are only reachable by scrolling."""
        result = drive.run(["END", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn("latex", result.selection)

    def test_page_down_moves_past_the_fold(self):
        result = drive.run(["PGDN", "SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn("latex", result.selection)

    def test_page_up_moves_back_toward_the_top(self):
        """From the last module, one page up runs out of list and stops on the
        first, so the cursor can walk back down to a row near the top."""
        result = drive.run(["END", "PGUP"] + drive.steps_to("gh") + ["SPACE", "ENTER", "y"])
        self.assertTrue(result.confirmed)
        self.assertIn("gh", result.selection)
        self.assertNotIn("latex", result.selection)

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

    def test_the_footer_says_how_many_ticked_rows_enter_installs(self):
        result = drive.run(["q"])
        self.assertIn("enter installs the %d ticked" % len(DEFAULTS), result.screen)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
