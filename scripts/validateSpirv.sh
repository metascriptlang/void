#!/bin/bash
# Validate every .spv file in a directory with naga; exit non-zero naming the first that fails.
# Usage: scripts/validateSpirv.sh [dir]   (default out/irPrograms, which scripts/regen-shaders.sh --check fills)
set -u
dir="${1:-out/irPrograms}"
command -v naga > /dev/null || { echo "validateSpirv: naga is not on PATH (cargo install naga-cli)"; exit 2; }
count=0
for file in "$dir"/*.spv; do
	[ -e "$file" ] || { echo "validateSpirv: no .spv file in $dir"; exit 2; }
	if ! naga "$file" > /dev/null 2> "$dir/naga.log"; then
		echo "validateSpirv: naga refused $file"
		cat "$dir/naga.log"
		exit 1
	fi
	count=$((count + 1))
done
rm -f "$dir/naga.log"
echo "validateSpirv: naga accepted $count files in $dir"
