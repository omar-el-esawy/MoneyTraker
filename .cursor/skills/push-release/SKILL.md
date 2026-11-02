---
name: push-release
description: >-
  Commit the Money Tracker release, push main, and push a vX.Y.Z tag so the
  Android release pipeline publishes the APK and updates the website. Use when
  the user says push a release, push the code with the tag, ship a version, or
  update the website through the pipeline.
disable-model-invocation: true
---

# Push a release

Do this only when the user asks to push a release. Push `main` and an annotated tag. Do not force-push, skip hooks, or change git config.

## Prepare

1. Stay on `main` and include only the release changes. Leave local scratch files out, including `site/mobile-check.html`.
2. Set `pubspec.yaml` `version` to the next patch, keeping the `+1` build suffix (`2.0.5+1`).
3. Write one Arabic paragraph to `site/next_changelog.txt`. The release workflow publishes it on the website and deletes the file. Match the tone of the previous note in `site/version.json`.
4. Commit on `main`. One or two sentences, focused on why.

## Push

The tag must match `v*.*.*` and be newer than the latest tag (`v2.0.5` is followed by `v2.0.6`).

```bash
git push origin HEAD
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

Push `main` before the tag. The tag points at the release commit.

## What the pipelines do

- Tag push starts **Release Android APK** (`.github/workflows/release.yml`). It builds the APK from the tag name, publishes the GitHub Release, then commits the website version to `main`.
- That website commit starts **Deploy website** (`.github/workflows/deploy-site.yml`) because `site/**` changed.

After the pushes, report the commit, the tag, and the Actions run URLs from `https://api.github.com/repos/omar-el-esawy/MoneyTraker/actions/runs?per_page=5`. The website version updates when the release run finishes, not when `main` is first pushed.
