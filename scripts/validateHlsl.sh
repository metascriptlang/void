#!/usr/bin/env sh
# -Zpc -O3 are the flags src/webgpu/d3d11/d3d11.c passes D3DCompile; keep them in step.
set -u
dir="${1:?usage: validateHlsl.sh <directory>}"
FXC="${FXC:-/c/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/fxc.exe}"
[ -x "$FXC" ] || { echo "validateHlsl: fxc not found at $FXC"; exit 2; }
count=0
for file in "$dir"/*.hlsl; do
	[ -e "$file" ] || { echo "validateHlsl: no .hlsl file in $dir"; exit 2; }
	case "$file" in
		*.vs.hlsl) profile=vs_5_0 ;;
		*.ps.hlsl) profile=ps_5_0 ;;
		*.cs.hlsl) profile=cs_5_0 ;;
		*) echo "validateHlsl: $file names no stage (.vs/.ps/.cs.hlsl)"; exit 1 ;;
	esac
	if ! "$FXC" -nologo -T "$profile" -E main -Zpc -O3 -Fo "$file.cso" "$file" > "$file.log" 2>&1; then
		cat "$file.log"
		echo "validateHlsl: fxc refused $file ($profile)"
		exit 1
	fi
	count=$((count + 1))
done
echo "validateHlsl: fxc accepted $count file(s) in $dir"
