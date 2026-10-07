"""Runtime loader for bare Galley grammar extensions.

``python -m galley <language-dir>`` builds a language package
whose inner extension (``galley_impl``) links the grammar statically.
This loader binds that file directly: ``.so`` in, parser out. No scan,
no hook wiring, no merging. The returned parser is the only handle:
a load registers nothing in ``sys.modules``.

```python
import galley

parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")
parser.install_procedure("reduction_Pair", lambda args: print("Pair"))
```

Bundled ``procedures.py`` hooks wire only through direct package
import (``import my_language``), never through this loader. A missing
file raises ``MissingArtifactError`` naming the path and the build
command; anything else surfaces the underlying error.

Every load hands out a new parser whose default hooks are its own
(none after a bare load), so loading one artifact twice never shares
hook state, and a dropped parser, its hooks and its sessions are freed.
The native image itself is shared by every parser of one file: it
cannot unload and holds no per-parser state, so the failure types
(``GalleyError``, ``StaleTreeError``) are the same objects across
those parsers. A failed load hands out no parser and leaves parsers
already handed out untouched; retrying after the cause is fixed is a
fresh attempt. Loads are safe from several threads at once.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
from types import ModuleType

from galley._constants import IMPL_MODULE_NAME as _IMPL_MODULE_NAME

__all__ = ["MissingArtifactError", "load"]


class MissingArtifactError(FileNotFoundError):
    """No compiled grammar where one was expected."""

    code = "galley:missing-artifact"


def _load_extension(path: Path) -> ModuleType:
    """Create and exec a fresh module from the extension file at ``path``.

    The extension uses multi-phase initialisation, so the import system
    builds a new module object for every call and keeps no copy of its
    namespace: dropping the parser frees it. The module is never
    registered in ``sys.modules``, so a failed load leaves nothing
    behind. The failure types and the hook index exist once per loaded
    image; the extension gives each module its own defaults and Session.
    """
    spec = importlib.util.spec_from_file_location(_IMPL_MODULE_NAME, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"not a loadable grammar extension: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load(path: str | Path) -> ModuleType:
    """Load the bare extension file at ``path`` and return its parser.

    Every call hands out a new parser: its default hooks are its own
    and a bare load installs none, so loading one artifact twice never
    shares hook state. No ``procedures.py`` scan: hook wiring beyond
    the build goes through the parser's ``install_procedure`` /
    ``install_procedures`` (the artifact's defaults, copied by sessions
    opened afterwards) or a session's own methods of the same names.

    Paths with an interior NUL byte are rejected loudly instead of
    truncated: like ``Session.parse_file``, this entry never lets a
    NUL cross into native code.
    """
    raw = os.fspath(path)
    if (isinstance(raw, bytes) and b"\0" in raw) or (
        isinstance(raw, str) and "\0" in raw
    ):
        raise ValueError(f"artifact path contains an interior NUL byte: {raw!r}")
    candidate = Path(raw)
    if not candidate.is_file():
        raise MissingArtifactError(
            f"no compiled grammar at {candidate}; "
            "build it with `python -m galley <language-dir>`"
        )
    return _load_extension(candidate)
