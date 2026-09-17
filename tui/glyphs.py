"""Box-drawing and marker characters, with an ASCII fallback.

Terminals without a UTF-8 locale render multi-byte glyphs as mojibake, so the
character set is chosen once at startup and never mixed.

The markers are checkboxes, MARKER_WIDTH cells wide in both tables. A round
dot read as decoration; a box reads as something to tick, which is what the
screen needs the person to understand before they press Enter.
"""

import os

# Cells every marker occupies. The screen writes fixed-width fields, so both
# tables have to agree on this.
MARKER_WIDTH = 3

UNICODE = {
    "checked": "[x]",
    "unchecked": "[ ]",
    "installed": "[\u2713]",
    "blocked": "[\u00d7]",
    "rule": "─",
    "cursor": "❯",
    "dot": "·",
    "more_up": "↑",
    "more_down": "↓",
    "more_left": "←",
    "more_right": "→",
}

ASCII = {
    "checked": "[x]",
    "unchecked": "[ ]",
    "installed": "[+]",
    "blocked": "[-]",
    "rule": "-",
    "cursor": ">",
    "dot": "-",
    "more_up": "^",
    "more_down": "v",
    "more_left": "<",
    "more_right": ">",
}


def pick():
    """Return the glyph table this terminal can actually render."""
    encoding = ""
    for name in ("LC_ALL", "LC_CTYPE", "LANG"):
        value = os.environ.get(name, "")
        if value:
            encoding = value
            break
    return UNICODE if "utf" in encoding.lower() else ASCII
