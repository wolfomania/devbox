"""Box-drawing and marker characters, with an ASCII fallback.

Terminals without a UTF-8 locale render multi-byte glyphs as mojibake, so the
character set is chosen once at startup and never mixed.
"""

import os

UNICODE = {
    "checked": "●",
    "unchecked": "○",
    "installed": "✓",
    "blocked": "×",
    "rule": "─",
    "cursor": "❯",
    "dot": "·",
}

ASCII = {
    "checked": "*",
    "unchecked": " ",
    "installed": "+",
    "blocked": "x",
    "rule": "-",
    "cursor": ">",
    "dot": "-",
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
