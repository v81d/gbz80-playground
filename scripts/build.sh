#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <asm file>"
    exit 1
fi

ASM_FILE="$1"
mkdir -p build

NAME=$(basename "$ASM_FILE" .asm)

rgbasm -Wall --color never -I src/ -o "build/$NAME.o" "$ASM_FILE"
rgblink --color never -o "build/$NAME.gb" -m "build/$NAME.map" "build/$NAME.o"
rgbfix --color never -p 0xff -v "build/$NAME.gb"

echo "Built build/$NAME.gb"
