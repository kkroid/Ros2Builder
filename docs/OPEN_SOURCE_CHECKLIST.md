# Open Source Release Checklist

Use this checklist before making the repository public.

## Required before publish

- Confirm the top-level `LICENSE` file is present and matches the intended Apache License 2.0 release.
- Confirm `.env`, `work/`, `ndk/` and packaged artifacts are not tracked.
- Run a secret/path scan over tracked files.
- Rebuild from a clean checkout using only documented commands.
- Note the exact package set that has been compiled and whether it has been tested on a device.
- Decide whether issues and pull requests should be enabled on the hosting platform.

## Recommended validation

```bash
git status --short
git ls-files
docker compose build
docker compose run --rm android-build
```

If a full rebuild is too expensive before every release, at least run manifest validation:

```bash
docker compose run --rm android-build python3 /scripts/validate_sources.py --manifest /manifests/ros2-humble-android.repos --src /work/src --check-existing
```

## Current project status

- Android target: `arm64-v8a`, API 29 by default.
- Default package set: `rclcpp rmw_fastrtps_cpp std_msgs`.
- Build status: initial Android compile path has been exercised locally.
- Runtime status: Android device or APK integration testing is still pending.