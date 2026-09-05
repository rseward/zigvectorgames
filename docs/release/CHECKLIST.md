# Release Checklist

This document outlines the standard procedure for performing a new release of the vgame vector game platform.

## Pre-Release Steps

1.  **Verify Clean Build**: Run `make build && make build-samples` to confirm the platform and all sample games compile cleanly with the target Zig version.
2.  **Verify Clean Working Tree**: Run `git status` — there should be no uncommitted changes.
3.  **Write Release Notes**: Prepend a user-facing summary of changes to `RELEASE.md` under a new version heading. Summaries should be bullet points, written in language an end user would understand.
4.  **Bump Version Numbers**: Update the version in:
    - `build.zig.zon` (`.version` field) — the platform library version
    - `examples/vecinvaders/build.zig.zon` (`.version` field) — if the sample version should track independently
5.  **Commit**: Stage all changes (`git add`) and commit with a descriptive message (e.g., `0.2.0 release`).

## Release Steps

6.  **Tag the Release**: Create an annotated git tag matching the version (e.g., `git tag -a v0.1.0 -m "v0.1.0 — initial release"`).
7.  **Push the Tag**: Push the tag to the remote (e.g., `git push origin v0.1.0`).
8.  **Push the Branch**: Push the branch to the remote if not already done (e.g., `git push origin zig-0.15.2`).

## Post-Release Steps

9.  **Verify**: Confirm the tag and commit appear on the remote repository.
10. **GitHub Release**: Create a GitHub release from the tag with the release notes from `RELEASE.md`.
11. **Communicate**: Inform users of the new release and its changes.