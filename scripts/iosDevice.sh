#!/usr/bin/env bash
# Runs a capture entry on a physical iPhone or iPad (Metal) from this Mac.
#
#   bash scripts/iosDevice.sh golden <device> [name]
#     every golden scene on <device>, copied to out/golden/metal-<name>/ and judged against
#     tests/golden/d3d11 with the @metal budgets; <name> is ios-<model> when left out
#   bash scripts/iosDevice.sh samples <device>
#     tests/integration/viewSamples.ms at 1, 2, 4 and 8 samples
#
# <device> is `auto` (the first paired, reachable iPhone or iPad), or an identifier, UDID or
# name from `xcrun devicectl list devices`. VOID_IOS_PROFILE names a development
# .mobileprovision; unset, the first one under the Xcode and MobileDevice profile folders that
# lists the device's UDID, allows get-task-allow and covers dev.void.* (a wildcard app id does).
# Every failure to reach a device exits 1 with a line starting `iosDevice:` that names the fix.
set -eu

mode="${1:?usage: iosDevice.sh golden <device> [name] | samples <device>}"
device="${2:?iosDevice.sh: name a device from xcrun devicectl list devices, or auto}"
mkdir -p out/ios

die() { echo "iosDevice: $*"; exit 1; }

field() { plutil -extract "$2" raw -o - "$1" 2> /dev/null || true; }

xcrun devicectl list devices --json-output out/ios/devices.json > out/ios/devices.log 2>&1 \
	|| die "devicectl cannot list devices (xcode-select must point at Xcode) — see out/ios/devices.log"
want=$device
device=""
for ((i = 0; ; i++)); do
	id=$(field out/ios/devices.json "result.devices.$i.identifier")
	[ -n "$id" ] || break
	udid=$(field out/ios/devices.json "result.devices.$i.hardwareProperties.udid")
	dname=$(field out/ios/devices.json "result.devices.$i.deviceProperties.name")
	platform=$(field out/ios/devices.json "result.devices.$i.hardwareProperties.platform")
	paired=$(field out/ios/devices.json "result.devices.$i.connectionProperties.pairingState")
	tunnel=$(field out/ios/devices.json "result.devices.$i.connectionProperties.tunnelState")
	reachable=0
	[ "$paired" = paired ] && [ "$tunnel" != unavailable ] && reachable=1
	if [ "$want" = auto ]; then
		case "$platform" in iOS | iPadOS) ;; *) continue ;; esac
		[ "$reachable" -eq 1 ] || continue
	else
		[ "$want" = "$id" ] || [ "$want" = "$udid" ] || [ "$want" = "$dname" ] || continue
		[ "$reachable" -eq 1 ] || die "device '$dname' is $paired and $tunnel — attach it, unlock it and trust this Mac"
	fi
	device=$id
	hwudid=$udid
	model=$(field out/ios/devices.json "result.devices.$i.hardwareProperties.marketingName" | tr -c 'A-Za-z0-9\n' '-' | sed 's/--*/-/g; s/-$//')
	break
done
if [ -z "$device" ]; then
	[ "$want" = auto ] && die "no paired, reachable iPhone or iPad — attach and unlock one, or name one from xcrun devicectl list devices"
	die "device '$want' is not in xcrun devicectl list devices — attach and pair it, or use auto"
fi

profile="${VOID_IOS_PROFILE:-}"
if [ -z "$profile" ]; then
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	for candidate in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision \
		"$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision; do
		[ -f "$candidate" ] || continue
		security cms -D -i "$candidate" > out/ios/candidate.plist 2> /dev/null || continue
		plutil -extract ProvisionedDevices xml1 -o - out/ios/candidate.plist 2> /dev/null | grep -q "<string>$hwudid</string>" || continue
		[ "$(field out/ios/candidate.plist Entitlements.get-task-allow)" = true ] || continue
		[ "$(field out/ios/candidate.plist ExpirationDate)" \> "$now" ] || continue
		appid=$(field out/ios/candidate.plist Entitlements.application-identifier)
		case "${appid#*.}" in
			'*') ;;
			*'*') case dev.void.golden in "${appid#*.}"*) ;; *) continue ;; esac ;;
			*) continue ;;
		esac
		profile=$candidate
		break
	done
	[ -n "$profile" ] || die "no development profile lists $model ($hwudid) with a wildcard app id covering dev.void.* — set VOID_IOS_PROFILE to one, or add the device in Xcode"
fi
[ -f "$profile" ] || die "VOID_IOS_PROFILE=$profile is not a file"
echo "iosDevice: $model ($device), profile $(basename "$profile")"

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
		|| die "install on $model failed ($(grep -m1 -iE 'error|locked|trust|profile' "out/ios/$name.install.log" || echo 'no reason logged')) — unlock it; a profile error means set VOID_IOS_PROFILE; see out/ios/$name.install.log"
}

# launch <bundle id> <environment JSON>: the app's console output
launch() {
	timeout 120 xcrun devicectl device process launch --device "$device" --console --terminate-existing \
		--environment-variables "$2" "$1" 2>&1 | tee out/ios/launch.log || true
}

case "$mode" in
golden)
	name="${3:-ios-$model}"
	. scripts/goldenDefines.sh
	# shellcheck disable=SC2086
	buildApp tests/golden/runner.ms VoidGolden dev.void.golden $GOLDEN_DEFINES --release
	count=$(launch dev.void.golden '{"VOID_SCENE_LIST":"1"}' | grep -c "$(printf '\t')" || true)
	[ "$count" -gt 0 ] || die "the runner listed no scenes — unlock $model and keep it awake ($(grep -iom1 'unable to launch[^.]*' out/ios/launch.log || echo 'see out/ios/launch.log'))"
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
