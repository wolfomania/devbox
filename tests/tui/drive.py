"""Drive the selection screen the way a terminal does, and read back the result.

The screen is a curses program, so it cannot be tested by calling functions:
what broke it once was the bytes a terminal sends for an arrow key, which only
appear when there is a real pty on the other end. Every test here starts
tui/app.py under a pty, writes keystrokes into it, and reads the selection file
it leaves behind.

Also usable by hand:

    python3 tests/tui/drive.py DOWN DOWN SPACE ENTER
"""

import os
import pty
import select
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tui"))

import manifest as manifest_mod  # noqa: E402  (needs ROOT on the path first)

# Terminal size to emulate. Deliberately the classic 80x24: the module list is
# taller than that, and rows below the fold were once unreachable.
LINES = 24
COLUMNS = 80

# Longest wait for the screen to settle after a keystroke, longest wait for the
# program to exit once the keys run out, and the gap in output that counts as
# the screen having finished drawing.
SETTLE_SECONDS = 2.0
EXIT_SECONDS = 5.0
QUIET_SECONDS = 0.08

# What a terminal actually puts on the wire.
#
# CSI is what a terminal in normal cursor mode sends; SS3 is what it sends in
# application cursor mode, which is the only form the xterm terminfo entry
# lists. Both are tested, because the screen has to survive either.
KEYS = {
    "UP": b"\x1b[A",
    "DOWN": b"\x1b[B",
    "RIGHT": b"\x1b[C",
    "LEFT": b"\x1b[D",
    "HOME": b"\x1b[H",
    "END": b"\x1b[F",
    "PGUP": b"\x1b[5~",
    "PGDN": b"\x1b[6~",
    "SS3_UP": b"\x1bOA",
    "SS3_DOWN": b"\x1bOB",
    "SS3_HOME": b"\x1bOH",
    "SS3_END": b"\x1bOF",
    "SHIFT_TAB": b"\x1b[Z",
    "ESC": b"\x1b",
    "ENTER": b"\r",
    "NEWLINE": b"\n",
    "SPACE": b" ",
}


class Result:
    """What one run of the screen produced."""

    def __init__(self, status, selection, screen):
        self.status = status
        self.selection = selection
        self.screen = screen

    @property
    def confirmed(self):
        return self.status == 0

    @property
    def quit(self):
        return self.status == 2


def key_bytes(name):
    """Bytes for a named key, or for a literal single character."""
    if name in KEYS:
        return KEYS[name]
    if len(name) == 1:
        return name.encode()
    raise KeyError("no such key: %s" % name)


def catalogue(manifest=None):
    return manifest_mod.load(manifest or os.path.join(ROOT, "manifests"))


def steps_to(module_id, manifest=None):
    """The DOWN presses that move the cursor from the top to this module.

    The cursor starts on the first module and skips category headings, so the
    count is just the module's position in the catalogue.
    """
    ids = [m.id for m in catalogue(manifest).modules]
    return ["DOWN"] * ids.index(module_id)


def write_state(path, installed):
    """Write a probe result file marking these module ids as installed."""
    with open(path, "w", encoding="utf-8") as handle:
        for module in catalogue().modules:
            if module.id in installed:
                handle.write("%s\tinstalled\t%s 1.0\n" % (module.id, module.id))
            else:
                handle.write("%s\tmissing\t\n" % module.id)
    return path


def run(keys, state="", manifest=None, can_root=1, lines=LINES, columns=COLUMNS):
    """Run the selection screen, send these keys, return what came back."""
    out_dir = tempfile.mkdtemp(prefix="devbox-tui-")
    out_path = os.path.join(out_dir, "selection")
    argv = [
        sys.executable,
        os.path.join(ROOT, "tui", "app.py"),
        "--manifest", manifest or os.path.join(ROOT, "manifests"),
        "--state", state,
        "--out", out_path,
        "--machine", "test machine",
        "--can-root", str(can_root),
    ]
    # A terminal whose terminfo entry lists only the SS3 arrow forms, which is
    # the case the screen used to fail on.
    env = dict(os.environ, TERM="xterm-256color", LANG="C.UTF-8", LINES=str(lines), COLUMNS=str(columns))

    pid, fd = pty.fork()
    if pid == 0:
        _set_window_size(lines, columns)
        os.execve(argv[0], argv, env)

    screen = b""
    try:
        screen += _drain(fd, SETTLE_SECONDS)
        for name in keys:
            os.write(fd, key_bytes(name))
            screen += _drain(fd, SETTLE_SECONDS)
        screen += _drain(fd, SETTLE_SECONDS)
        status = _wait(pid, fd)
    finally:
        os.close(fd)

    selection = []
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as handle:
            selection = [line for line in handle.read().split("\n") if line]
    return Result(status, selection, screen.decode("utf-8", "replace"))


def _set_window_size(lines, columns):
    import fcntl
    import struct
    import termios

    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", lines, columns, 0, 0))


def _drain(fd, seconds, quiet=QUIET_SECONDS):
    """Read what the screen writes, until it goes quiet or the time runs out.

    Waiting a fixed slice per keystroke would make the suite as slow as its
    most sluggish case; waiting for the redraw to stop keeps it honest on a
    loaded machine and quick on an idle one.
    """
    chunks = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], quiet)
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


def _wait(pid, fd):
    """Exit status of the screen, killing it if it will not leave."""
    deadline = time.time() + EXIT_SECONDS
    while time.time() < deadline:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            return os.waitstatus_to_exitcode(status)
        _drain(fd, 0.05)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    raise AssertionError("the selection screen did not exit")


def _main(argv):
    result = run(argv)
    print("exit status: %d" % result.status)
    print("selection:")
    for module_id in result.selection:
        print("  " + module_id)
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
