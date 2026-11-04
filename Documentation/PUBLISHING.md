# Publishing MemoLine on GitHub

## Repository contents

Commit the source, tests, scripts and documentation. Do not commit `.build/`, `build/`, `dist/`, `.DS_Store`, personal note data, signing certificates or Apple credentials.

## Create a source repository

From the MemoLine directory:

```sh
git init
git add .
git status
git commit -m "Initial open source release"
git branch -M main
git remote add origin https://github.com/YOUR_NAME/MemoLine.git
git push -u origin main
```

Before `git commit`, inspect `git status` and confirm that only project files are staged.

## Create the unsigned release archive

```sh
bash scripts/package-release.sh
```

The script creates these ignored local artifacts:

```text
dist/MemoLine-<version>-macOS-<architecture>.zip
dist/SHA256SUMS.txt
```

This release is ad-hoc signed, not Developer ID signed and not notarized. State that prominently in every release description.

## Create a GitHub Release

1. Open the repository on GitHub.
2. Select **Releases → Draft a new release**.
3. Create tag `v1.10` from branch `main`.
4. Use title `MemoLine 1.10`.
5. Copy the text from `Documentation/RELEASE_NOTES_1.10.md`.
6. Attach the ZIP file and `SHA256SUMS.txt` from `dist/`.
7. Mark it as a pre-release while the application is not notarized.
8. Publish the release.

Never upload the entire `build/` or `.build/` directory. Never upload the user's `memos.json`.
