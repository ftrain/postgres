#!/bin/bash
# PostgreSQL Encyclopedia Build Script
# Compiles markdown files into EPUB and PDF formats using pandoc

set -e  # Exit on error

ENCYCLOPEDIA_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$ENCYCLOPEDIA_DIR/output"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "PostgreSQL Encyclopedia Build Script"
echo "====================================="
echo ""

# Check for pandoc
if ! command -v pandoc &> /dev/null; then
    echo "ERROR: pandoc is not installed"
    echo ""
    echo "Please install pandoc:"
    echo "  Ubuntu/Debian: sudo apt-get install pandoc texlive-xelatex"
    echo "  macOS: brew install pandoc basictex"
    echo "  Windows: choco install pandoc miktex"
    echo ""
    exit 1
fi

echo "Found pandoc: $(pandoc --version | head -1)"
echo ""

# Define chapter order
CHAPTERS=(
    "README.md"
    "00-introduction.md"
)

# Add all subsystem chapters (these were created by exploration agents)
# Note: Actual chapter files would be in their respective directories
# This is a template showing the intended structure

echo "Building EPUB..."
pandoc \
    --from markdown \
    --to epub \
    --output "$OUTPUT_DIR/postgresql-encyclopedia.epub" \
    --toc \
    --toc-depth=3 \
    --epub-metadata=metadata.xml \
    --epub-cover-image=cover.png \
    --number-sections \
    --standalone \
    "${CHAPTERS[@]}" \
    appendices/glossary.md

echo "✓ EPUB created: $OUTPUT_DIR/postgresql-encyclopedia.epub"
echo ""

echo "Building PDF..."
pandoc \
    --from markdown \
    --to pdf \
    --output "$OUTPUT_DIR/postgresql-encyclopedia.pdf" \
    --toc \
    --toc-depth=3 \
    --number-sections \
    --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V fontsize=10pt \
    -V documentclass=book \
    -V classoption=openany \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -V toccolor=black \
    --highlight-style=tango \
    "${CHAPTERS[@]}" \
    appendices/glossary.md

echo "✓ PDF created: $OUTPUT_DIR/postgresql-encyclopedia.pdf"
echo ""

echo "Building HTML..."
pandoc \
    --from markdown \
    --to html5 \
    --output "$OUTPUT_DIR/postgresql-encyclopedia.html" \
    --toc \
    --toc-depth=3 \
    --number-sections \
    --standalone \
    --self-contained \
    --css=styles.css \
    --highlight-style=tango \
    "${CHAPTERS[@]}" \
    appendices/glossary.md

echo "✓ HTML created: $OUTPUT_DIR/postgresql-encyclopedia.html"
echo ""

echo "================================================"
echo "Build complete! Files created in: $OUTPUT_DIR"
echo "================================================"
echo ""
echo "Files:"
echo "  - postgresql-encyclopedia.epub"
echo "  - postgresql-encyclopedia.pdf"
echo "  - postgresql-encyclopedia.html"
echo ""

# Generate file statistics
echo "Statistics:"
echo "  EPUB size: $(du -h "$OUTPUT_DIR/postgresql-encyclopedia.epub" | cut -f1)"
echo "  PDF size: $(du -h "$OUTPUT_DIR/postgresql-encyclopedia.pdf" | cut -f1)"
echo "  HTML size: $(du -h "$OUTPUT_DIR/postgresql-encyclopedia.html" | cut -f1)"
echo ""
