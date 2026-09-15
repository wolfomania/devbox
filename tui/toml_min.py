"""Minimal TOML reader for Python versions without ``tomllib`` (before 3.11).

Supports exactly the subset ``manifest.toml`` uses: comments, ``[table]``
headers, ``[[array-of-table]]`` headers, and values that are strings, integers,
booleans or flat arrays of strings. Anything else raises, loudly, rather than
being silently misread.
"""

_BOOLEANS = {"true": True, "false": False}


class TomlError(ValueError):
    """Raised when the manifest contains syntax this reader does not support."""


def _split_comment(line):
    """Strip a trailing comment, honouring quotes so ``"a # b"`` survives."""
    quote = None
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#":
            return line[:index]
    return line


def _parse_array(raw, lineno):
    body = raw[1:-1].strip()
    if not body:
        return []
    return [_parse_value(item.strip(), lineno) for item in body.split(",") if item.strip()]


def _parse_value(raw, lineno):
    raw = raw.strip()
    if not raw:
        raise TomlError("empty value on line %d" % lineno)
    if raw[0] == '"' and raw[-1] == '"':
        return raw[1:-1]
    if raw[0] == "'" and raw[-1] == "'":
        return raw[1:-1]
    if raw[0] == "[":
        if raw[-1] != "]":
            raise TomlError("multi-line arrays are not supported (line %d)" % lineno)
        return _parse_array(raw, lineno)
    if raw in _BOOLEANS:
        return _BOOLEANS[raw]
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        raise TomlError("unsupported value %r on line %d" % (raw, lineno))


def loads(text):
    """Parse TOML text into a dict. Mirrors ``tomllib.loads`` for our subset."""
    root = {}
    current = root

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = _split_comment(raw_line).strip()
        if not line:
            continue

        if line.startswith("[["):
            if not line.endswith("]]"):
                raise TomlError("unterminated table header on line %d" % lineno)
            name = line[2:-2].strip()
            current = {}
            root.setdefault(name, []).append(current)
            continue

        if line.startswith("["):
            if not line.endswith("]"):
                raise TomlError("unterminated table header on line %d" % lineno)
            name = line[1:-1].strip()
            current = root.setdefault(name, {})
            continue

        if "=" not in line:
            raise TomlError("expected key = value on line %d" % lineno)

        key, _, value = line.partition("=")
        current[key.strip()] = _parse_value(value, lineno)

    return root


def load(handle):
    return loads(handle.read())
