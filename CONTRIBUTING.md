# Contributing

Thanks for helping improve this ROS 2 Humble Android build workspace.

## Project scope

This repository contains Docker Compose configuration, source manifests and helper scripts for cross-compiling selected ROS 2 Humble packages to Android. It does not vendor ROS 2 source code, Android NDK archives, build trees or packaged artifacts.

Good contributions include:

- reproducible build fixes for Android `arm64-v8a`;
- manifest corrections that keep repository URLs and versions explicit;
- scripts that make source fetching, building or packaging safer;
- documentation for verified package sets, Android runtime requirements and known failures.

## Development flow

1. Copy `.env.example` to `.env` and keep local paths, proxies and caches out of Git.
2. Run `docker compose build` after Dockerfile changes.
3. Run `docker compose run --rm prepare-ndk` when changing NDK-related settings.
4. Run `docker compose run --rm fetch-sources` after manifest changes.
5. Run `docker compose run --rm builder bash /scripts/build_android.sh` for build changes.
6. Run `docker compose run --rm package-artifacts` for packaging changes.

For faster review, include the exact `BUILD_PACKAGES`, `ANDROID_ABI`, `ANDROID_API`, host OS, Docker version and the failing command when reporting a problem.

## Repository hygiene

Do not commit these local outputs:

- `.env` or other local environment files;
- `work/` source checkouts, build logs, install trees or packaged artifacts;
- `ndk/` caches and downloaded archives.

If a change requires a local patch to upstream ROS 2 or DDS source, keep the patch in `scripts/apply_android_patches.sh` and document why it is needed.

## License

The project license has not been selected yet. Choose and add a `LICENSE` file before publishing the repository as open source.