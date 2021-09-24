#!/bin/bash

# Convert one or more SVG to PNGs.
# Dependencies: cairosvg
# Example usage: ./gen.sh trondelan-2021

set -eu

tmp_file="$(mktemp)"
png_width=8000

trap "rm $tmp_file" EXIT

if (( $# < 1 )); then
    echo "Usage: $0 <input-dirs ...>" 2>&1
    echo "Example: $0 *" 2>&1
    exit 1
fi

for input_dir in "$@"; do
    if [[ ! -d $input_dir ]]; then
        echo "Input dir isn't a dir, skipping: $input_dir" 2>&1
        continue
    fi
    output_dir="$input_dir/export"
    if [[ -e $output_dir && ! -d $output_dir ]]; then
        echo "Output dir exists but isn't dir, ending: $output_dir" 2>&1
        exit 0
    fi
    mkdir -p "$output_dir"

    for file in $(ls -1 "$input_dir" | egrep '.svg$'); do
        input_file="$input_dir/$file"
        output_base_file="$output_dir/${file%.svg}"
        if [[ ! -f $input_file ]]; then
            continue
        fi

        echo
        echo "Converting: $input_file"

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

        # Create temporary to filter bad content
        cat < "$input_file" > "$tmp_file"
        sed -i 's/xlink://g' "$tmp_file"

        # Generate PDF
        cairosvg "$tmp_file" -o "$output_base_file.pdf" -f pdf

        # Generate PNG
        cairosvg "$tmp_file" -o "$output_base_file.png" -f png --output-width "$png_width" --output-height "$png_height"
    done
done
