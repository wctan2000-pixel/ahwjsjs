# WC Recharge iOS 1.0.17 verification

Source package: `WC_Source_117_Clone_Candidate`.

Checks completed in this environment:

- Swift syntax parse: PASS
- `Info.plist`: PASS
- Xcode `project.pbxproj`: PASS
- `login-context.js` regression test: PASS
- `private-rules.js` regression test: PASS
- `panel.html`: SHA-256 matches Android 1.0.17 source
- `login-context.js`: SHA-256 matches Android 1.0.17 source
- `private-rules.js`: SHA-256 matches Android 1.0.17 source
- `recent-links.js`: SHA-256 matches Android 1.0.17 source
- All Swift source files and all four bundled web resources are referenced by the Xcode target.

The current container is not macOS and does not contain Xcode/iPhoneOS SDK. The included GitHub Actions macOS workflow performs the real Xcode compile and creates the unsigned IPA.
