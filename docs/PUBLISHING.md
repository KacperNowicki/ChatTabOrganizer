# Publishing

This repository is prepared for GitHub hosting and manual CurseForge upload.

## Privacy Check

Before publishing, verify:

- No local filesystem paths are committed.
- No API keys, CurseForge tokens, GitHub tokens, or private account data are committed.
- `LICENSE` matches the rights you want to grant publicly.

## Build A Release Zip

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

This creates:

```text
dist/ChatTabsOrganizer-<version>.zip
```

The zip contains one top-level folder:

```text
ChatTabsOrganizer/
```

That folder contains the `.toc` and Lua files that World of Warcraft loads.

## CurseForge

For a first CurseForge release:

1. Create a new World of Warcraft addon project on CurseForge.
2. Select Retail as the supported game flavor.
3. Use the version from `ChatTabsOrganizer/ChatTabsOrganizer.toc`.
4. Upload the generated zip from `dist/`.
5. Use the changelog entry from `CHANGELOG.md`.
6. Choose a project license deliberately. The repository currently uses all rights reserved.

CurseForge automation can be added later after you have a CurseForge project ID and an API token. Do not commit the API token; store it as a GitHub Actions secret.

## GitHub Release

Attach the generated zip to a GitHub release. A good first tag is:

```text
v0.1.9
```
