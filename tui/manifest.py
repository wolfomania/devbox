"""Read ``manifest.toml`` into module records, and answer queries from shell.

``tomllib`` is used where available (Python 3.11+); older interpreters fall back
to the vendored reader in ``toml_min``. Records are frozen: nothing downstream
mutates the catalogue it was handed.
"""

import os
import sys
from dataclasses import dataclass, field

try:
    import tomllib as _toml

    def _load_text(text):
        return _toml.loads(text)

except ImportError:  # Python < 3.11
    import toml_min as _toml

    def _load_text(text):
        return _toml.loads(text)


STATUS_INSTALLED = "installed"
STATUS_MISSING = "missing"
STATUS_UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class Module:
    id: str
    name: str
    category: str
    summary: str
    script: str
    pin: str
    pin_kind: str
    pin_extra: str = ""
    default: bool = False
    required: bool = False
    needs_root: bool = False
    size_mb: int = 0
    requires: tuple = ()

    @classmethod
    def from_dict(cls, raw):
        return cls(
            id=raw["id"],
            name=raw["name"],
            category=raw["category"],
            summary=raw.get("summary", ""),
            script=raw["script"],
            pin=str(raw.get("pin", "")),
            pin_kind=raw.get("pin_kind", "none"),
            pin_extra=str(raw.get("pin_extra", "")),
            default=bool(raw.get("default", False)),
            required=bool(raw.get("required", False)),
            needs_root=bool(raw.get("needs_root", False)),
            size_mb=int(raw.get("size_mb", 0)),
            requires=tuple(raw.get("requires", ())),
        )


@dataclass(frozen=True)
class Catalogue:
    modules: tuple
    categories: tuple

    def by_id(self, module_id):
        for module in self.modules:
            if module.id == module_id:
                return module
        raise KeyError(module_id)

    def in_category(self, category):
        return tuple(m for m in self.modules if m.category == category)


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = _load_text(handle.read())

    modules = tuple(Module.from_dict(raw) for raw in data.get("module", ()))
    seen = []
    for module in modules:
        if module.category not in seen:
            seen.append(module.category)
    return Catalogue(modules=modules, categories=tuple(seen))


def resolve_order(catalogue, selected_ids):
    """Order the selection so every dependency is installed before its dependent.

    Dependencies are pulled in even when the user did not tick them.
    """
    ordered = []
    visiting = set()

    def visit(module_id):
        if module_id in ordered or module_id in visiting:
            return
        visiting.add(module_id)
        module = catalogue.by_id(module_id)
        for dependency in module.requires:
            visit(dependency)
        visiting.discard(module_id)
        if module_id not in ordered:
            ordered.append(module_id)

    manifest_order = [m.id for m in catalogue.modules]
    for module_id in sorted(selected_ids, key=manifest_order.index):
        visit(module_id)
    return ordered


def _cli(argv):
    """Query interface for install.sh. Keeps TOML parsing in one place."""
    here = os.path.dirname(os.path.abspath(__file__))
    manifest_path = os.environ.get("DVB_MANIFEST", os.path.join(here, os.pardir, "manifest.toml"))
    catalogue = load(manifest_path)

    if not argv or argv[0] == "ids":
        print("\n".join(m.id for m in catalogue.modules))
        return 0

    command = argv[0]

    if command == "rows":
        # id, script, needs_root, pin, pin_extra, name - tab separated for read(1)
        for m in catalogue.modules:
            print("\t".join([m.id, m.script, "1" if m.needs_root else "0", m.pin, m.pin_extra, m.name]))
        return 0

    if command == "defaults":
        print("\n".join(m.id for m in catalogue.modules if m.default or m.required))
        return 0

    if command == "field" and len(argv) == 3:
        print(getattr(catalogue.by_id(argv[1]), argv[2]))
        return 0

    if command == "order":
        print("\n".join(resolve_order(catalogue, argv[1:])))
        return 0

    print("usage: manifest.py [ids|rows|defaults|order IDS...|field ID NAME]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
