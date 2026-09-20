"""Runtime loader for bare Galley grammar extensions.

``python -m galley <language-dir>`` builds a language package
whose inner extension (``galley_impl``) links the grammar statically.
This loader binds that file directly: ``.so`` in, module out. No scan,
no hook wiring, no merging. Prefer the returned module over importing
``galley_impl``: the ``sys.modules`` key aliases the most recent load
while every loaded object stays alive in the cache.

```python
import galley

parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")
parser.install_procedure("reduction_Pair", lambda args: print("Pair"))
```

Bundled ``procedures.py`` hooks wire only through direct package
import (``import my_language``), never through this loader. A missing
file raises ``MissingArtifactError`` naming the path and the build
command; anything else surfaces the underlying error. Loaded modules
stay cached by real path for the process lifetime under the single
``sys.modules`` key: last load wins the key, the cache holds every
object. A failed load restores the previous entry instead of evicting
it. Loads are not thread-safe: load every artifact once at
startup.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

from galley._constants import IMPL_MODULE_NAME as _IMPL_MODULE_NAME

__all__ = ["MissingArtifactError", "load"]


class MissingArtifactError(FileNotFoundError):
    """No compiled grammar where one was expected."""

    code = "galley:missing-artifact"


_artifact_cache: dict[str, ModuleType] = {}


def _load_extension(path: Path) -> ModuleType:
    """Exec the extension file at ``path`` under the constant stem."""
    spec = importlib.util.spec_from_file_location(_IMPL_MODULE_NAME, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"not a loadable grammar extension: {path}")
    module = importlib.util.module_from_spec(spec)
    previous = sys.modules.get(_IMPL_MODULE_NAME)
    sys.modules[_IMPL_MODULE_NAME] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        if previous is None:
            sys.modules.pop(_IMPL_MODULE_NAME, None)
        else:
            sys.modules[_IMPL_MODULE_NAME] = previous
        raise
    return module


def load(path: str | Path) -> ModuleType:
    """Load the bare extension file at ``path`` and return its module.

    No ``procedures.py`` scan: hook wiring beyond the build goes
    through the module's ``install_procedure`` / ``install_procedures``
    directly, where the shared-registry semantics are visible.
    """
    candidate = Path(path)
    if not candidate.is_file():
        raise MissingArtifactError(
            f"no compiled grammar at {candidate}; "
            "build it with `python -m galley <language-dir>`"
        )
    key = str(candidate.resolve())
    if key in _artifact_cache:
        module = _artifact_cache[key]
        sys.modules[_IMPL_MODULE_NAME] = module
        return module
    module = _load_extension(candidate)
    _artifact_cache[key] = module
    return module
