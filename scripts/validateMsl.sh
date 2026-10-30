#!/usr/bin/env sh
# No options, as src/webgpu/metal/metal.m passes newLibraryWithSource; keep them in step.
set -u
dir="${1:?usage: validateMsl.sh <directory>}"
xcrun -sdk macosx -f metal > /dev/null 2>&1 || { echo "validateMsl: xcrun metal not found (macOS only)"; exit 2; }
count=0
for file in "$dir"/*.metal; do
	[ -e "$file" ] || { echo "validateMsl: no .metal file in $dir"; exit 2; }
	case "$file" in
		*.metal_ios.*) sdk=iphoneos ;;
		*) sdk=macosx ;;
	esac
	if ! xcrun -sdk "$sdk" metal -c "$file" -o "$file.air" > "$file.log" 2>&1; then
		cat "$file.log"
		echo "validateMsl: metal refused $file ($sdk)"
		exit 1
	fi
	count=$((count + 1))
done
echo "validateMsl: metal accepted $count file(s) in $dir"
