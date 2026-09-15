"""What the prompt between installs must do, checked through a real pty.

The prompt that reopens the selection screen reads one keypress. That only
behaves like a keypress when there is a real terminal on the other end: asked
for a whole line instead, `q` did nothing until it was followed by enter,
which is neither what the prompt says nor what a one-key prompt suggests.

The prompt lives in install.sh, so these tests load that file with its final
`main "$@"` removed and call the function directly.
"""

import os
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Longest wait for the prompt to answer, and the gap in output that counts as
# it having finished writing.
REPLY_SECONDS = 5.0
QUIET_SECONDS = 0.08

# What pause_for_menu returns: 0 reopens the selection screen, 1 leaves.
#
# Only the prompt is called. Nothing detects the machine and nothing installs,
# so running this changes nothing about the box it runs on.
HARNESS = """
. "$(dirname -- "$0")/install.sh.nomain"
pause_for_menu
printf 'RESULT=%d\\n' "$?"
"""


def harness_dir():
    """A directory install.sh will accept as its own repository root.

    install.sh works its root out from $0 and downloads the repository when
    the libraries are not beside it, so the harness cannot simply live in
    /tmp: it would bootstrap a real devbox and install on this machine. A
    symlinked lib/ is all it needs to recognise the tree it is already in.
    """
    tmp_dir = tempfile.mkdtemp(prefix="devbox-prompt-")
    os.symlink(os.path.join(ROOT, "lib"), os.path.join(tmp_dir, "lib"))

    with open(os.path.join(ROOT, "install.sh"), encoding="utf-8") as handle:
        lines = handle.read().splitlines(True)
    assert lines[-1].strip() == 'main "$@"', lines[-1]
    with open(os.path.join(tmp_dir, "install.sh.nomain"), "w", encoding="utf-8") as handle:
        handle.writelines(lines[:-1])

    script = os.path.join(tmp_dir, "harness.sh")
    with open(script, "w", encoding="utf-8") as handle:
        handle.write(HARNESS)
    return script


def ask(keys, with_tty=True):
    """Run the prompt, send these bytes, return (exit code it reported, output)."""
    script = harness_dir()
    env = dict(os.environ, TERM="xterm-256color", NO_COLOR="1")

    if not with_tty:
        done = subprocess.run(
            ["sh", script], input=keys, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        return _result(done.stdout.decode("utf-8", "replace"))

    pid, fd = pty.fork()
    if pid == 0:
        os.execve("/bin/sh", ["sh", script], env)

    output = b""
    try:
        output += _drain(fd)
        os.write(fd, keys)
        output += _drain(fd)
        os.waitpid(pid, 0)
    finally:
        os.close(fd)
    return _result(output.decode("utf-8", "replace"))


def _result(text):
    for line in text.splitlines():
        if line.startswith("RESULT="):
            return int(line[len("RESULT="):]), text
    raise AssertionError("the prompt never reported a result:\n" + text)


def _drain(fd, seconds=REPLY_SECONDS):
    chunks = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], QUIET_SECONDS)
        if not readable:
            if chunks:
                break
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:  # the child closed the pty
            break
        if not data:
            break
        chunks += data
    return chunks


class PromptTest(unittest.TestCase):
    def test_a_bare_q_leaves(self):
        """The regression: no enter after it."""
        status, _ = ask(b"q")
        self.assertEqual(status, 1)

    def test_a_bare_enter_reopens_the_selection_screen(self):
        status, _ = ask(b"\r")
        self.assertEqual(status, 0)

    def test_q_is_taken_either_case(self):
        status, _ = ask(b"Q")
        self.assertEqual(status, 1)

    def test_any_other_key_reopens_the_selection_screen(self):
        status, _ = ask(b"x")
        self.assertEqual(status, 0)

    def test_the_prompt_says_which_keys_it_takes(self):
        _, text = ask(b"q")
        self.assertIn("press enter for the selection screen, q to quit", text)

    def test_the_terminal_is_left_echoing(self):
        """Raw mode is the tool, not the state it leaves behind."""
        before = subprocess.run(["stty", "-g"], capture_output=True, text=True)
        ask(b"q")
        after = subprocess.run(["stty", "-g"], capture_output=True, text=True)
        self.assertEqual(before.stdout, after.stdout)

    def test_without_a_terminal_it_still_reads_a_line(self):
        """A captured session has no tty to put into raw mode; q typed on a
        line of its own has to keep working there."""
        self.assertEqual(ask(b"q\n", with_tty=False)[0], 1)
        self.assertEqual(ask(b"\n", with_tty=False)[0], 0)


if __name__ == "__main__":
    sys.exit(not unittest.main(exit=False, verbosity=2).result.wasSuccessful())
