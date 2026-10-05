# Isolated regression checks

Run `./scripts/check.sh` from the repository root. No package installation or
test target modification is needed. The script links objects from the app it
just built, so Debug and Release checks use their respective production objects.

`CommitTests.m` exercises eight cases in the real controller: Space's first,
remembered, out-of-range and explicit candidate choices; newline and Tab
insertion; a clicked candidate after the active client changes; and an empty
candidate list. It checks inserted text, clearing composition/candidates and
Space passthrough. IMK client/panel services are stand-ins. Controllers are
allocated without IMK server initialization and kept alive for this short
process. This is deliberately not an IMK lifecycle, UI or ownership test.

`EngineTests.m` uses copied resources from the built app in a separate test
bundle. It checks required resources, the preferences plist, 15 exact UTF-8
parser results, SQLite integrity, a real ICU regex/dictionary lookup and
autocorrect loading with an existing emoticon. It neither links CacheManager
nor instantiates Suggestion, so it does not access learned data. Nib existence
does not prove that preferences or candidate UI work.

`DependencyProbe.c` opens the app's direct system dependencies in a native
process and checks their loaded CPU types, including shared-cache libraries.
The build script separately inspects every bundled Mach-O and load path.

## Fixture provenance

`transliteration.json` was captured on 2026-10-05 by compiling the **unchanged**
upstream `AvroParser.m` and loading its original `data.json`, exported from
commit `107a73283ac34a33faf7f6799c2e9dbfa97e6643` into a separate directory.
The baseline did not use the working controller changes. The capture used
native arm64 Xcode 27.0 and SDK 27.0.

| Baseline file | SHA-256 |
| --- | --- |
| `AvroParser.m` | `1e3e19594fd2c537d10338d600b62c1aac31ba1290a4fc72f0bbe56ada2147f9` |
| `data.json` | `a29c7682f826eea55bc1d77b3ffea2dd1f00d8f0d2471b394f71d4d1fdf17c1a` |

Each fixture is the result of `[[AvroParser sharedInstance] parse:input]`.
These are compatibility snapshots from known upstream source, not a complete
linguistic specification or independently authored upstream test suite. `ami`
was also confirmed interactively by the user. Deliberately preserved examples
include `123.45` becoming `১২৩।৪৫`, `12:30` becoming `১২ঃ৩০`, and `o` followed
by a backtick becoming an empty string. The test compares UTF-8 bytes without Unicode normalization.
Do not regenerate expected results from modified code merely to make a test
pass; explain and review intentional transliteration changes separately.
