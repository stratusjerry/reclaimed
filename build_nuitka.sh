#!/bin/bash
set -e

# Build a standalone binary using Nuitka
# Requires: pip install nuitka ordered-set
# Linux also requires: sudo apt install patchelf

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VERSION=$(grep -o '__version__ = "[^"]*"' reclaimed/version.py | cut -d'"' -f2)

echo -e "${YELLOW}Building reclaimed v${VERSION} static binary with Nuitka...${NC}"

# Check for nuitka
if ! python -m nuitka --version &> /dev/null; then
    echo -e "${RED}Nuitka not found. Install with: pip install nuitka ordered-set${NC}"
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
echo -e "${YELLOW}Compiling static binary...${NC}"
python -m nuitka \
    --onefile \
    --standalone \
    --output-dir=dist \
    --output-filename="$OUTPUT_NAME" \
    --include-package=reclaimed \
    --include-package-data=reclaimed \
    --include-data-files="$IO_PY=io.py" \
    --include-data-files="$RICH_UNICODE_DIR/*.py=rich/_unicode_data/" \
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
