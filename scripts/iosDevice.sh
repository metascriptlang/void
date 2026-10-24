#!/usr/bin/env bash
# Runs a capture entry on a physical iPhone or iPad (Metal) from this Mac.
#
#   VOID_IOS_PROFILE=<file.mobileprovision> bash scripts/iosDevice.sh golden <device> <name>
#     every golden scene on <device>, copied to out/golden/metal-<name>/ and judged against
#     tests/golden/d3d11 with the @metal budgets
#   VOID_IOS_PROFILE=<file.mobileprovision> bash scripts/iosDevice.sh samples <device>
#     tests/integration/viewSamples.ms at 1, 2, 4 and 8 samples
#
# <device> is an identifier from `xcrun devicectl list devices`. The profile is a development
# profile that names the device and an app id covering dev.void.* (a team wildcard does).
set -eu

mode="${1:?usage: iosDevice.sh golden <device> <name> | samples <device>}"
device="${2:?iosDevice.sh: name a device from xcrun devicectl list devices}"
profile="${VOID_IOS_PROFILE:?iosDevice.sh: set VOID_IOS_PROFILE to a development .mobileprovision}"
mkdir -p out/ios

security cms -D -i "$profile" > out/ios/profile.plist
team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' out/ios/profile.plist)
sdk=$(xcrun -sdk iphoneos --show-sdk-path)
clang=$(xcrun --find clang)
target=arm64-apple-ios15.0

# buildApp <entry.ms> <name> <bundle id> [msc flags...]
buildApp() {
	local entry=$1 name=$2 id=$3
	shift 3
	local app=out/ios/$name.app
	"$clang" -c -fobjc-arc -target $target -isysroot "$sdk" src/examples/iosAppEntry.m -o out/ios/iosAppEntry.o
	if ! MSC_NO_GLOBAL_CACHE=1 msc build "$@" "$entry" --os=ios --cpu=arm64 "--link=$PWD/out/ios/iosAppEntry.o" \
		--cc="$clang" "--passC=-target $target -isysroot \"$sdk\"" "--passL=-target $target -isysroot \"$sdk\"" \
		--output="out/ios/$name.bin" > "out/ios/$name.build.log" 2>&1; then
		echo "iosDevice: $entry does not build for iOS — see out/ios/$name.build.log"
		exit 1
	fi
	rm -rf "$app"
	mkdir -p "$app/tests"
	cp "out/ios/$name.bin" "$app/$name"
	cp -R assets "$app/assets"
	cp -R tests/fonts "$app/tests/fonts"
	cp "$profile" "$app/embedded.mobileprovision"
	cat > "$app/Info.plist" <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0"><dict>
	<key>CFBundleIdentifier</key><string>$id</string>
	<key>CFBundleExecutable</key><string>$name</string>
	<key>CFBundleName</key><string>$name</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
	<key>MinimumOSVersion</key><string>15.0</string>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string><string>metal</string></array>
	<key>UILaunchScreen</key><dict/>
	<key>UIStatusBarHidden</key><true/>
	</dict></plist>
	EOF
	cat > "out/ios/$name.entitlements" <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0"><dict>
	<key>application-identifier</key><string>$team.$id</string>
	<key>com.apple.developer.team-identifier</key><string>$team</string>
	<key>get-task-allow</key><true/>
	</dict></plist>
	EOF
	codesign --force --sign "Apple Development" --entitlements "out/ios/$name.entitlements" --timestamp=none "$app"
	xcrun devicectl device install app --device "$device" "$app" > "out/ios/$name.install.log" 2>&1 \
		|| { echo "iosDevice: install on $device failed — see out/ios/$name.install.log"; exit 1; }
}

# launch <bundle id> <environment JSON>: the app's console output
launch() {
	timeout 120 xcrun devicectl device process launch --device "$device" --console --terminate-existing \
		--environment-variables "$2" "$1" 2>&1 || true
}

case "$mode" in
golden)
	name="${3:?iosDevice.sh golden: name the device set, as in out/golden/metal-<name>}"
	. scripts/goldenDefines.sh
	# shellcheck disable=SC2086
	buildApp tests/golden/runner.ms VoidGolden dev.void.golden $GOLDEN_DEFINES --release
	count=$(launch dev.void.golden '{"VOID_SCENE_LIST":"1"}' | grep -c "$(printf '\t')")
	[ "$count" -gt 0 ] || { echo "iosDevice: the runner listed no scenes"; exit 1; }
	failed=0
	for ((i = 0; i < count; i++)); do
		verdict=$(launch dev.void.golden "{\"VOID_SCENE\":\"$i\"}" | grep -E '^(CAPTURED|FAIL)' || true)
		case "$verdict" in
			CAPTURED*) ;;
			*) echo "FAIL scene $i: ${verdict:-no verdict}"; failed=$((failed + 1)) ;;
		esac
	done
	[ "$failed" -eq 0 ] || { echo "iosDevice: $failed of $count scenes were not captured"; exit 1; }
	rm -rf "out/golden/metal-$name"
	xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
		--domain-identifier dev.void.golden --source Documents/out/golden/metal \
		--destination "out/golden/metal-$name" > out/ios/copy.log 2>&1
	# The comparator reads out/golden/<VOID_CONFORM>; it judges the device set as metal for
	# the @metal budgets, so the Mac's own set steps aside for the run.
	MSC_NO_GLOBAL_CACHE=1 msc build tests/golden/compare.ms --output=out/goldenCompare.exe > /dev/null
	[ ! -e out/golden/metal ] || mv out/golden/metal out/golden/metal-host
	ln -s "metal-$name" out/golden/metal
	status=0
	VOID_CONFORM=metal out/goldenCompare.exe > "out/golden-metal-$name.log" 2>&1 || status=$?
	unlink out/golden/metal
	[ ! -e out/golden/metal-host ] || mv out/golden/metal-host out/golden/metal
	echo "$name: $(grep -E '^golden metal' "out/golden-metal-$name.log") — see out/golden-metal-$name.log"
	exit "$status"
	;;
samples)
	buildApp tests/integration/viewSamples.ms VoidSamples dev.void.samples
	for samples in 1 2 4 8; do
		echo "$samples: $(launch dev.void.samples "{\"VOID_VIEW_SAMPLES\":\"$samples\"}" \
			| grep -E '^(PASS|FAIL)|not supported' | tr '\n' ' ')"
	done
	;;
*)
	echo "iosDevice.sh: the mode is golden or samples, not '$mode'"
	exit 2
	;;
esac
