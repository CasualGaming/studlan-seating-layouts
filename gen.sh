#!/bin/bash

# Convert one or more SVG to PNGs and PDFs.
# Will recursively find all SVG files in the specified dir or file and
# convert them to PNGs and PDFs in a new "export" dir in the same dir as the SVG file.
# Make sure the provided paths don't overlap.

# Dependencies: cairosvg
# Usage: ./gen.sh <input-dirs-or-files>
# Example usage: ./gen.sh trondelan-2021

set -eu

export png_width=8000

if (( $# < 1 )); then
    echo "Usage: $0 <input-dirs-or-files ...>" 2>&1
    echo "Example: $0 *" 2>&1
    exit 1
fi

# Check if required commands are present
command -v parallel &> /dev/null || echo "parallel not found, please install it." >&2 && exit 1
command -v cairosvg &> /dev/null || echo "cairosvg not found, please install it." >&2 && exit 1

# Process a single SVG file
# Arg 1: Full file path
function gen_file {
    input_file="$1"
    file_basename="$(basename "$1")"
    file_basename="${file_basename%.svg}"
    input_dir="$(dirname "$input_file")"
    export_dir="$input_dir/export"

    echo "Converting file: $input_file"

    if [[ ! -f $input_file ]]; then
        echo "Input file isn't a file, skipping: $input_file" 2>&1
        continue
    fi

    # Setup tmp-file for temporary processing later
    tmp_file="$(mktemp)"
    trap "rm $tmp_file" EXIT

    # Figure out dims
    # Example: viewBox="-0.080299786 0 1000.101 1116"
    dims="$(grep -m1 -oP '(?<=viewBox=")[]+ +[0-9-.]+ +[0-9-.]+ +[0-9-.]+(?=")' "$input_file" || true)"
    x1="$(echo "$dims" | cut -d' ' -f1)"
    y1="$(echo "$dims" | cut -d' ' -f2)"
    x2="$(echo "$dims" | cut -d' ' -f3)"
    y2="$(echo "$dims" | cut -d' ' -f4)"
    width=
    height=
    if [[ $x1 != "" && $y1 != "" && $x2 != "" && $y2 != "" ]]; then
        width=$(echo "$x2 - $x1" | bc -l)
        height=$(echo "$y2 - $y1" | bc -l)
    fi
    if [[ $width == "" || $height == "" ]]; then
        # Example: <svg height="1000" width="1000">
        dims="$(grep -m1 '<svg ' "$input_file" || true)"
        width="$(echo "$dims" | grep -oP '(?<=width=")[0-9-.]+(?=(px)?")' || true)"
        height="$(echo "$dims" | grep -oP '(?<=height=")[0-9-.]+(?=(px)?")' || true)"
    fi
    if [[ $width == "" || $height == "" ]]; then
        echo "SVG dims not found for image, skipping: $input_file" 2>&1
        continue
    fi
    #echo "WIDTH=$width HEIGHT=$height"
    png_height=$(echo "$png_width / $width * $height" | bc -l)
    png_height=${png_height%.*}
    #echo "PNG_WIDTH=$png_width PNG_HEIGHT=$png_height"
    if [[ $png_height == "" ]] || (( png_height <= 0 )); then
        echo "Unable to determine output height, skipping: $input_file" 2>&1
        continue
    fi

    # Create temporary file to filter bad content
    cat < "$input_file" > "$tmp_file"
    sed -i 's/xlink://g' "$tmp_file"

    # Generate PDF
    cairosvg "$tmp_file" -o "$export_dir/$file_basename.pdf" -f pdf

    # Generate PNG
    cairosvg "$tmp_file" -o "$export_dir/$file_basename.png" -f png --output-width "$png_width" --output-height "$png_height"
}
export -f gen_file

# Delete old exports
for input_element in "$@"; do
    for export_dir in $(find "$input_element" -type d -name 'export'); do
        echo "Deleting old export dir: $export_dir"
    done
done


# Create new export dirs and record input files
declare -a input_files
for input_element in "$@"; do
    for input_file in $(find "$input_element" -type f -name '*.svg'); do
        input_files+=("$input_file")
        mkdir -p "$(dirname "$input_file")/export"
    done
done

# Process files in parallel
parallel gen_file ::: "${input_files[@]}"
