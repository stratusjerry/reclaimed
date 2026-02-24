"""Nuitka build entry point — uses absolute imports for standalone compilation."""
import importlib.util
import os
import sys

# Fix rich._unicode_data dynamic imports under Nuitka.
#
# rich lazily loads unicode data files (e.g. unicode17-0-0.py) via
# importlib.import_module, but these have hyphens in their names so
# Nuitka can't compile them as regular modules. We bundle them as data
# files and pre-register them in sys.modules so import_module finds them.
_candidates = [
    os.path.dirname(os.path.abspath(__file__)),
    os.path.dirname(os.path.abspath(sys.executable)),
]

for _base in _candidates:
    _udata = os.path.join(_base, "rich", "_unicode_data")
    if os.path.isdir(_udata):
        for _fname in os.listdir(_udata):
            if _fname.startswith("unicode") and _fname.endswith(".py"):
                _mod_name = f"rich._unicode_data.{_fname[:-3]}"
                if _mod_name not in sys.modules:
                    _fpath = os.path.join(_udata, _fname)
                    _spec = importlib.util.spec_from_file_location(_mod_name, _fpath)
                    if _spec and _spec.loader:
                        _mod = importlib.util.module_from_spec(_spec)
                        sys.modules[_mod_name] = _mod
                        _spec.loader.exec_module(_mod)
        break

from reclaimed.cli import main

if __name__ == "__main__":
    main()
