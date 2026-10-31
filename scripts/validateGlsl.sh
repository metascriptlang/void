#!/bin/sh
# Validate every GLSL 430 and ES 3.00 stage in a directory with glslang; exit non-zero naming the first that fails.
# Usage: scripts/validateGlsl.sh [dir]   (default out/irPrograms, which scripts/regen-shaders.sh --check fills)
# Files go to glslang in batches, each compiled on its own, since one process per file costs minutes.
set -u
dir="${1:-out/irPrograms}"
command -v glslang > /dev/null || { echo "validateGlsl: glslang is not on PATH (scoop install glslang)"; exit 2; }
list="$dir/glslang.list"
ls "$dir"/*.vert "$dir"/*.frag "$dir"/*.comp 2> /dev/null > "$list"
count=$(wc -l < "$list" | tr -d ' ')
[ "$count" -gt 0 ] || { rm -f "$list"; echo "validateGlsl: no GLSL stage in $dir"; exit 2; }
if ! xargs -n 200 glslang < "$list" > /dev/null 2>&1; then
	while read -r file; do
		if ! glslang "$file" > "$dir/glslang.log" 2>&1; then
			echo "validateGlsl: glslang refused $file"
			cat "$dir/glslang.log"
			rm -f "$list"
			exit 1
		fi
	done < "$list"
fi
rm -f "$list" "$dir/glslang.log"
echo "validateGlsl: glslang accepted $count files in $dir"
