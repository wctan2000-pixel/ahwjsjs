# WC Recharge iOS 1.0.17

Native iOS/WKWebView port of the supplied `WC_Source_117_Clone_Candidate` source.

## Included

- Xcode project: `WCRechargeIOS.xcodeproj`
- App source: `WCRechargeIOS/`
- Android 1.0.17 web assets copied into the iOS bundle: `panel.html`, `login-context.js`, `private-rules.js`, `recent-links.js`
- Windows/GitHub one-click unsigned IPA workflow: `.github/workflows/build-ipa.yml`
- Build steps: `BUILD_IPA_WINDOWS_GITHUB.txt`

## Local verification performed

- Swift syntax parse passed.
- `Info.plist` and Xcode `project.pbxproj` lint passed.
- Login-context offline regression tests passed.
- Private-rules offline regression tests passed.
- The four bundled web assets above were checked against the supplied Android 1.0.17 source; hashes match.

## Build

On Windows, follow `BUILD_IPA_WINDOWS_GITHUB.txt`. The workflow outputs `WCRechargeIOS-unsigned.ipa`, which must then be signed with your own iOS signing method.
