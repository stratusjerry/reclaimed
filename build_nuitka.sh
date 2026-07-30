#!/bin/bash
set -e

# Build a standalone binary using Nuitka
# Requires: pip install nuitka==4.1.3 ordered-set
# Linux also requires: sudo apt install patchelf
# Windows: needs Zig, pinned below to a version known to work with --lto=yes (see PIN_ZIG_VERSION)

# Zig version to pin on Windows. Nuitka's --zig backend always fetches the
# latest ziglang from PyPI with no version pin of its own; ziglang 0.16.0
# (current latest as of writing) fails to link with --lto=yes, producing
# "undefined symbol" errors (frexpf, wmemchr, isnan, __QNAN, ...) from
# zigc.lib. 0.14.1 is confirmed working with this Nuitka release; 0.13.0 is
# too old to support the C23 `#embed` directive Nuitka's zig backend relies on.
PIN_ZIG_VERSION="0.14.1"

# LTO is on by default: it makes the binary noticeably smaller (dead-code
# elimination across the whole link) at the cost of a much slower build —
# the linking step alone can take several minutes longer. Override with
# LTO=no ./build_nuitka.sh for a quicker, larger build during iteration.
LTO="${LTO:-yes}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VERSION=$(grep -o '__version__ = "[^"]*"' reclaimed/version.py | cut -d'"' -f2)

echo -e "${YELLOW}Building reclaimed v${VERSION} static binary with Nuitka...${NC}"

# Check for nuitka (import check only — invoking the `nuitka` CLI, even
# with --version, triggers its C-compiler probe, which on Windows prompts
# to download Zig and hangs here since stdin isn't a real answer source)
if ! python -c "import nuitka" &> /dev/null; then
    echo -e "${RED}Nuitka not found. Install with: pip install nuitka==4.1.3 ordered-set${NC}"
    exit 1
fi

# Locate the Python stdlib io.py (needed for Nuitka runtime init)
IO_PY=$(python -c "import io; print(io.__file__)")
if [ ! -f "$IO_PY" ]; then
    echo -e "${RED}Could not locate stdlib io.py${NC}"
    exit 1
fi

# Locate rich's _unicode_data directory (contains hyphenated .py files
# that Nuitka can't compile as modules — they must be bundled as data)
RICH_UNICODE_DIR=$(python -c "import rich._unicode_data; import os; print(os.path.dirname(rich._unicode_data.__file__))")
if [ ! -d "$RICH_UNICODE_DIR" ]; then
    echo -e "${RED}Could not locate rich/_unicode_data directory${NC}"
    exit 1
fi

# Clean previous build artifacts
echo -e "${YELLOW}Cleaning previous build artifacts...${NC}"
rm -rf dist/ nuitka_main.dist/ nuitka_main.build/ nuitka_main.onefile-build/

# Platform-specific flags
PLATFORM_FLAGS=()
case "$(uname -s)" in
    Linux*)
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows*)
        PLATFORM_FLAGS+=("--zig")

        # Pre-seed Nuitka's private pip cache with the pinned Zig version
        # (see PIN_ZIG_VERSION above) so Nuitka's own auto-download of the
        # unpinned latest ziglang never kicks in. Nuitka treats the package
        # as "installed" as soon as the folder exists, regardless of version,
        # so this only needs to run once per machine.
        PRIVATE_PIP_DIR=$(python -c "from nuitka.utils.PrivatePipSpace import getPrivatePipBaseFolder; print(getPrivatePipBaseFolder())")
        ZIG_SITE_PACKAGES="$PRIVATE_PIP_DIR/Lib/site-packages"
        if [ ! -d "$ZIG_SITE_PACKAGES/ziglang-$PIN_ZIG_VERSION.dist-info" ]; then
            echo -e "${YELLOW}Pinning Zig to ${PIN_ZIG_VERSION} in Nuitka's cache...${NC}"
            python -m pip install --no-warn-script-location \
                --target "$ZIG_SITE_PACKAGES" --upgrade \
                "ziglang==$PIN_ZIG_VERSION"
        fi
        ;;
    Darwin*)
        # macOS: no special flags needed
        ;;
esac

OUTPUT_NAME="reclaimed"
if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]] || [[ "$(uname -s)" == CYGWIN* ]]; then
    OUTPUT_NAME="reclaimed.exe"
fi

# Build static binary
echo -e "${YELLOW}Compiling static binary (LTO=${LTO})...${NC}"
python -m nuitka \
    --onefile \
    --standalone \
    --output-dir=dist \
    --output-filename="$OUTPUT_NAME" \
    --include-package=reclaimed \
    --include-package-data=reclaimed \
    --include-data-files="$IO_PY=io.py" \
    --include-data-files="$RICH_UNICODE_DIR/*.py=rich/_unicode_data/" \
    --lto="$LTO" \
    --remove-output \
    --assume-yes-for-downloads \
    "${PLATFORM_FLAGS[@]}" \
    nuitka_main.py

echo -e "${GREEN}Build complete!${NC}"

if [ -f "dist/$OUTPUT_NAME" ]; then
    SIZE=$(ls -lh "dist/$OUTPUT_NAME" | awk '{print $5}')
    echo -e "${GREEN}Binary: dist/$OUTPUT_NAME ($SIZE)${NC}"
    echo -e "${GREEN}Test with: dist/$OUTPUT_NAME --help${NC}"
fi
