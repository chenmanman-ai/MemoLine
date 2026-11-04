# Privacy

MemoLine is designed to work entirely on the user's Mac.

- No account is required.
- No analytics, advertising SDK, telemetry or crash-reporting service is included.
- No note content is transmitted over the network.
- MemoLine does not monitor screenshots, screen recordings or the clipboard.
- Notes and their local backup are stored under `~/Library/Application Support/MemoLine/`.
- Preferences are stored in the standard macOS preferences domain `local.memoline.desktop`.
- Notification permission is requested only after the user creates a reminder.

macOS may contact Apple when checking a downloaded application or delivering a local notification. Those operating-system services are outside MemoLine's control.

To remove local MemoLine data, quit the application first, then delete `~/Library/Application Support/MemoLine/`. This cannot be undone unless the user has another backup.
