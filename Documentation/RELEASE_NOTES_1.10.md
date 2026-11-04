# MemoLine 1.10

MemoLine is a lightweight, local macOS memo app. Short notes hang from a rope at the top of the screen and remain entirely on the user's Mac.

## Requirements

- macOS 14 or later
- The downloaded build supports the architecture named in the ZIP filename

## Install

1. Download the MemoLine ZIP and `SHA256SUMS.txt` from this release.
2. Optionally verify the ZIP with `shasum -a 256 -c SHA256SUMS.txt` in Terminal.
3. Unzip it and drag `MemoLine.app` into the Applications folder.
4. Try to open MemoLine once.
5. This build is not notarized. If macOS blocks it, open **System Settings → Privacy & Security**, find the MemoLine message, choose **Open Anyway**, then confirm **Open**.
6. MemoLine appears in the menu bar. On its first successful launch, the memo rope opens briefly so the user can create the first note.

Only bypass macOS security for a download obtained from this repository whose checksum matches the release checksum.

## Privacy

No account, network service, analytics, screenshot monitoring or clipboard monitoring is included. See `PRIVACY.md` for storage and removal details.

## Attribution

MemoLine is an independent adaptation of MIT-licensed Tendedero source code. It is not an official Tendedero release and is not endorsed by its author. See `LICENSE`, `LICENSE-MEMOLINE` and `THIRD_PARTY_NOTICES.md`.
