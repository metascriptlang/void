#!/bin/bash
# Validate every .wgsl file in a directory with naga; exit non-zero naming the first that fails.
# Usage: scripts/validateWgsl.sh [dir]   (default out/wgslProbe, which src/test/shaderWgslCheck.ms writes)
set -u
dir="${1:-out/wgslProbe}"
command -v naga > /dev/null || { echo "validateWgsl: naga is not on PATH (cargo install naga-cli)"; exit 2; }
count=0
for file in "$dir"/*.wgsl; do
	[ -e "$file" ] || { echo "validateWgsl: no .wgsl file in $dir"; exit 2; }
	if ! naga "$file" > /dev/null 2> "$dir/naga.log"; then
		echo "validateWgsl: naga refused $file"
		cat "$dir/naga.log"
		exit 1
	fi
	count=$((count + 1))
done
rm -f "$dir/naga.log"
echo "validateWgsl: naga accepted $count files in $dir"
