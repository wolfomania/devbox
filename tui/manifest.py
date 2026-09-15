"""Read ``manifest.toml`` into module records, and answer queries from shell.

``tomllib`` is used where available (Python 3.11+); older interpreters fall back
to the vendored reader in ``toml_min``. Records are frozen: nothing downstream
mutates the catalogue it was handed.
"""

import glob
import os
import sys
from dataclasses import dataclass

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
class Category:
    """A group of modules, usually one manifest file."""

    id: str
    title: str
    order: int


@dataclass(frozen=True)
class Catalogue:
    modules: tuple
    categories: tuple

    def by_id(self, module_id):
        for module in self.modules:
            if module.id == module_id:
                return module
        raise KeyError(module_id)

    def in_category(self, category_id):
        return tuple(m for m in self.modules if m.category == category_id)


def manifest_files(path):
    """Resolve a manifest path to the list of files to read, in load order.

    A directory is read as ``*.toml`` sorted by name, so a numeric prefix
    controls the order categories appear in. A single file still works.
    """
    if os.path.isdir(path):
        return sorted(glob.glob(os.path.join(path, "*.toml")))
    return [path]


def _read_file(path, fallback_order):
    """Parse one manifest file into (category, modules)."""
    with open(path, "r", encoding="utf-8") as handle:
        data = _load_text(handle.read())

    header = data.get("manifest", {})
    modules = []
    category = None

    for raw in data.get("module", ()):
        if "category" not in raw:
            if "category" not in header:
                raise ValueError("%s: module %r has no category, and the file "
                                 "declares no [manifest] category" % (path, raw.get("id")))
            raw = dict(raw, category=header["category"])
        modules.append(Module.from_dict(raw))
        if category is None:
            category = raw["category"]

    if category is not None:
        category = Category(
            id=header.get("category", category),
            title=header.get("title", category.replace("-", " ").title()),
            order=int(header.get("order", fallback_order)),
        )
    return category, modules


def load(path):
    """Load one manifest file, or every ``*.toml`` in a manifest directory."""
    categories = {}
    modules = []

    for index, file_path in enumerate(manifest_files(path)):
        category, found = _read_file(file_path, fallback_order=index * 10)
        for module in found:
            if any(m.id == module.id for m in modules):
                raise ValueError("%s: duplicate module id %r" % (file_path, module.id))
            modules.append(module)
        if category is not None and category.id not in categories:
            categories[category.id] = category

    ordered = tuple(sorted(categories.values(), key=lambda c: (c.order, c.id)))
    by_category = {c.id: i for i, c in enumerate(ordered)}
    modules.sort(key=lambda m: by_category.get(m.category, len(ordered)))
    return Catalogue(modules=tuple(modules), categories=ordered)


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
    manifest_path = os.environ.get("DVB_MANIFEST", os.path.join(here, os.pardir, "manifests"))
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

    if command == "pins" and len(argv) == 2:
        # The pinned version and its companion pin, for the module whose script
        # is at this path. Modules use it to look up their own pin.
        wanted = argv[1]
        for m in catalogue.modules:
            if m.script == wanted:
                print("%s\t%s" % (m.pin, m.pin_extra))
                return 0
        print("manifest.py: no module with script %r" % wanted, file=sys.stderr)
        return 1

    if command == "field" and len(argv) == 3:
        print(getattr(catalogue.by_id(argv[1]), argv[2]))
        return 0

    if command == "order":
        print("\n".join(resolve_order(catalogue, argv[1:])))
        return 0

    print("usage: manifest.py [ids|rows|defaults|order IDS...|field ID NAME|pins SCRIPT]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
