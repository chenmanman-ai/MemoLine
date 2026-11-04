# Contributing

Contributions that keep MemoLine lightweight, local and native to macOS are welcome.

## Before opening a pull request

1. Build on macOS 14 or later with Swift 5.9 or later.
2. Run `bash scripts/test.sh`.
3. Run `swift build --product MemoLine`.
4. Do not add accounts, analytics, advertising, cloud synchronization or network dependencies without prior discussion.
5. Do not add Tendedero branding, icons or documentation images.
6. Do not commit `.build`, `build`, `dist`, user note files, notification data or signing credentials.

Keep persistence mutations inside `MemoStore`. Changes to the document format require backward-compatible decoding, failure-safe migration and regression tests.

By submitting a contribution, you agree that it may be distributed under the repository's MIT licenses.
