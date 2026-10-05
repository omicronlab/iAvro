#!/bin/bash
# Native build and isolated regression checks. Never installs or launches the IME.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
CONFIGURATION=${2:-Debug}
case "$CONFIGURATION" in Debug|Release) ;; *) echo "Use Debug or Release" >&2; exit 2 ;; esac
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
    echo "These checks require native arm64 macOS and full Xcode." >&2
    exit 2
fi
OUT=${1:-$(mktemp -d "${TMPDIR:-/tmp}/iavro-check.XXXXXX")}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd -P)
case "$OUT/" in "$ROOT/"*) echo "Use an output directory outside the checkout." >&2; exit 2 ;; esac
if [[ -n $(ls -A "$OUT") ]]; then
    echo "Output directory must be empty: $OUT" >&2
    exit 2
fi
printf 'Evidence: %s\n' "$OUT"

# Preserve each command's own status, including xcodebuild's, without a tee pipe.
run_logged() {
    local name=$1 status
    shift
    printf '%q ' "$@" > "$OUT/$name.command"
    printf '\n' >> "$OUT/$name.command"
    if "$@" > "$OUT/$name.log" 2>&1; then status=0; else status=$?; fi
    printf '%s\n' "$status" > "$OUT/$name.exit"
    printf '%s: exit %s\n' "$name" "$status"
    if [[ $status -ne 0 ]]; then tail -100 "$OUT/$name.log"; exit "$status"; fi
}

{
    uname -m
    sw_vers
    xcode-select -p
    printf 'DEVELOPER_DIR=%s\n' "${DEVELOPER_DIR:-<not overridden>}"
    xcodebuild -version
    xcrun --sdk macosx --show-sdk-path
    xcrun --sdk macosx --show-sdk-version
    xcrun --sdk macosx --show-sdk-build-version
    xcrun clang --version
    git -C "$ROOT" rev-parse HEAD
    git -C "$ROOT" status --short
} > "$OUT/environment.log"
cat "$OUT/environment.log"

cd "$ROOT"
BUILD=(/usr/bin/xcodebuild -project AvroKeyboard.xcodeproj -scheme "Avro Keyboard"
    -configuration "$CONFIGURATION" -destination 'generic/platform=macOS'
    -derivedDataPath "$OUT/DerivedData" ARCHS=arm64)
run_logged schemes /usr/bin/xcodebuild -project AvroKeyboard.xcodeproj -list
run_logged settings "${BUILD[@]}" -showBuildSettings
run_logged build "${BUILD[@]}" -resultBundlePath "$OUT/build.xcresult" build
grep 'warning:' "$OUT/build.log" > "$OUT/warnings.log" || true
printf 'Build warning lines: %s\n' "$(wc -l < "$OUT/warnings.log" | tr -d ' ')"

setting() { sed -n "s/^ *$1 = //p" "$OUT/settings.log"; }
APP="$(setting BUILT_PRODUCTS_DIR)/$(setting FULL_PRODUCT_NAME)"
OBJECTS="$(setting OBJECT_FILE_DIR_normal)/arm64"
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
[[ -f "$APP/Contents/MacOS/$EXECUTABLE" ]]
run_logged signature /usr/bin/codesign --verify --strict --verbose=2 "$APP"
/usr/bin/codesign -d --verbose=4 --entitlements - --xml "$APP" > "$OUT/signature-details.log" 2>&1
/usr/bin/plutil -p "$APP/Contents/Info.plist" > "$OUT/bundle-plist.log"

# Scan every bundled Mach-O, not merely the presumed main executable.
: > "$OUT/architectures.log"
: > "$OUT/load-commands.log"
: > "$OUT/dependencies.unsorted"
count=0
while IFS= read -r -d '' component; do
    description=$(/usr/bin/file -b "$component")
    case "$description" in *Mach-O*) ;; *) continue ;; esac
    count=$((count + 1))
    archs=$(/usr/bin/lipo -archs "$component")
    printf '%s\n%s\narchitectures: %s\n' "$component" "$description" "$archs" >> "$OUT/architectures.log"
    if [[ "$archs" != arm64 ]]; then echo "Unexpected bundled architecture: $archs" >&2; exit 1; fi
    /usr/bin/otool -L "$component" >> "$OUT/architectures.log"
    /usr/bin/otool -l "$component" >> "$OUT/load-commands.log"
    /usr/bin/otool -L "$component" | awk 'NR > 1 {sub(/^[ \t]+/, ""); sub(/ \(compatibility version.*$/, ""); print}' >> "$OUT/dependencies.unsorted"
done < <(/usr/bin/find "$APP" -type f -print0)
[[ $count -gt 0 ]]
printf 'Bundled Mach-O components: %s (arm64 only)\n' "$count"
LC_ALL=C sort -u "$OUT/dependencies.unsorted" > "$OUT/dependencies.txt"
dependencies=()
while IFS= read -r dependency; do
    case "$dependency" in
        /System/Library/*|/usr/lib/*) dependencies+=("$dependency") ;;
        *) echo "Unreviewed non-system dependency: $dependency" >&2; exit 1 ;;
    esac
done < "$OUT/dependencies.txt"
# The current app has no runpaths or embedded frameworks. Fail closed on changes
# until their resolution and architecture have been explicitly reviewed.
if grep -q 'cmd LC_RPATH' "$OUT/load-commands.log"; then
    echo "An LC_RPATH was introduced; review load paths before accepting." >&2
    exit 1
fi
run_logged dependency-probe-build xcrun clang -arch arm64 -Wall -Wextra \
    "$ROOT/tests/DependencyProbe.c" -o "$OUT/dependency-probe"
run_logged dependency-architectures "$OUT/dependency-probe" "${dependencies[@]}"

run_logged commit-tests-build xcrun clang -arch arm64 -fno-objc-arc -I "$ROOT" \
    -framework Cocoa -framework InputMethodKit "$ROOT/tests/CommitTests.m" \
    "$OBJECTS/AvroKeyboardController.o" -o "$OUT/commit-tests"
run_logged commit-tests "$OUT/commit-tests"
cat "$OUT/commit-tests.log"

# Copy built resources into a distinct test bundle for NSBundle mainBundle.
# This executable does not link CacheManager, instantiate an IMK server, or
# write the user's Avro preference/learning stores.
TEST_CONTENTS="$OUT/EngineTests.app/Contents"
mkdir -p "$TEST_CONTENTS/MacOS"
/usr/bin/ditto "$APP/Contents/Resources" "$TEST_CONTENTS/Resources"
cp "$ROOT/tests/transliteration.json" "$TEST_CONTENTS/Resources/transliteration.json"
/usr/bin/plutil -create xml1 "$TEST_CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string EngineTests "$TEST_CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string org.iavro.tests.EngineTests "$TEST_CONTENTS/Info.plist"
engine_objects=()
for name in AvroParser RegexParser Database FMDatabase FMResultSet FMDatabasePool AutoCorrect RegexKitLite; do
    engine_objects+=("$OBJECTS/$name.o")
done
run_logged engine-tests-build xcrun clang -arch arm64 -fno-objc-arc -I "$ROOT" \
    -framework Cocoa -licucore -lsqlite3 "$ROOT/tests/EngineTests.m" \
    "${engine_objects[@]}" -o "$TEST_CONTENTS/MacOS/EngineTests"
run_logged engine-tests "$TEST_CONTENTS/MacOS/EngineTests"
cat "$OUT/engine-tests.log"
printf 'PASS %s build and isolated checks. Logs: %s\n' "$CONFIGURATION" "$OUT"
printf 'This is a local ad-hoc build, not a distributable or notarized release.\n'
