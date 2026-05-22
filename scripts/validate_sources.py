#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(f"Duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_mapping,
)


def normalize_git_url(url):
    normalized = url.strip()
    if normalized.endswith("/"):
        normalized = normalized[:-1]
    if normalized.endswith(".git"):
        normalized = normalized[:-4]
    return normalized.lower()


def run_git(path, *args):
    result = subprocess.run(
        ["git", "-C", str(path), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as manifest_file:
        data = yaml.load(manifest_file, Loader=UniqueKeyLoader)

    repositories = data.get("repositories") if isinstance(data, dict) else None
    if not isinstance(repositories, dict):
        raise ValueError(
            "Manifest must contain a top-level 'repositories' mapping"
        )

    return repositories


def validate_manifest(repositories):
    errors = []
    urls = defaultdict(list)

    for repo_path, repo_info in repositories.items():
        if not isinstance(repo_info, dict):
            errors.append(f"{repo_path}: repository entry must be a mapping")
            continue

        repo_type = repo_info.get("type")
        repo_url = repo_info.get("url")
        repo_version = repo_info.get("version")

        if repo_type != "git":
            errors.append(
                f"{repo_path}: only git repositories are supported, "
                f"got {repo_type!r}"
            )
        if not repo_url:
            errors.append(f"{repo_path}: missing url")
        if not repo_version:
            errors.append(f"{repo_path}: missing version/tag/branch")
        if os.path.isabs(repo_path) or ".." in Path(repo_path).parts:
            errors.append(
                f"{repo_path}: repository path must be relative and stay "
                "inside src"
            )

        if repo_url and repo_version:
            urls[normalize_git_url(repo_url)].append(
                (repo_path, str(repo_version), repo_url)
            )

    for normalized_url, entries in urls.items():
        versions = {entry[1] for entry in entries}
        if len(entries) > 1:
            formatted = ", ".join(
                f"{path}@{version}" for path, version, _ in entries
            )
            if len(versions) > 1:
                errors.append(
                    "Duplicate repository URL with different versions: "
                    f"{formatted}"
                )
            else:
                errors.append(f"Duplicate repository URL: {formatted}")

    return errors


def check_existing_checkout(src_dir, repositories):
    errors = []
    warnings = []

    for repo_path, repo_info in repositories.items():
        checkout = src_dir / repo_path
        if not checkout.exists():
            continue

        if not (checkout / ".git").exists():
            errors.append(
                f"{repo_path}: path exists but is not a git checkout: "
                f"{checkout}"
            )
            continue

        expected_url = repo_info["url"]
        expected_version = str(repo_info["version"])
        code, actual_url, stderr = run_git(
            checkout,
            "config",
            "--get",
            "remote.origin.url",
        )
        if code != 0:
            errors.append(
                f"{repo_path}: cannot read git remote.origin.url: {stderr}"
            )
            continue

        if normalize_git_url(actual_url) != normalize_git_url(expected_url):
            errors.append(
                f"{repo_path}: remote mismatch, expected {expected_url}, "
                f"got {actual_url}"
            )

        code, current_head, stderr = run_git(checkout, "rev-parse", "HEAD")
        if code != 0:
            errors.append(f"{repo_path}: cannot read HEAD: {stderr}")
            continue

        version_candidates = [
            expected_version,
            f"origin/{expected_version}",
            f"refs/tags/{expected_version}",
            f"refs/remotes/origin/{expected_version}",
        ]
        matched_version = False
        for candidate in version_candidates:
            code, candidate_head, _ = run_git(
                checkout,
                "rev-parse",
                "--verify",
                f"{candidate}^{{commit}}",
            )
            if code == 0 and candidate_head == current_head:
                matched_version = True
                break

        if not matched_version:
            code, branch_name, _ = run_git(
                checkout,
                "rev-parse",
                "--abbrev-ref",
                "HEAD",
            )
            if code == 0 and branch_name == expected_version:
                matched_version = True

        if not matched_version:
            warnings.append(
                f"{repo_path}: checkout exists but HEAD does not exactly "
                f"match manifest version {expected_version}; run vcs pull "
                "or remove the checkout if this is unexpected"
            )

    return errors, warnings


def write_inventory(path, src_dir, repositories):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as inventory_file:
        inventory_file.write("path\turl\tversion\thead\n")
        for repo_path, repo_info in sorted(repositories.items()):
            checkout = src_dir / repo_path
            head = ""
            if (checkout / ".git").exists():
                code, head_value, _ = run_git(checkout, "rev-parse", "HEAD")
                if code == 0:
                    head = head_value
            inventory_file.write(
                f"{repo_path}\t{repo_info['url']}\t"
                f"{repo_info['version']}\t{head}\n"
            )


def main():
    parser = argparse.ArgumentParser(
        description="Validate ROS 2 source manifest and external checkouts"
    )
    parser.add_argument(
        "--manifest",
        required=True,
        help="Path to .repos manifest",
    )
    parser.add_argument(
        "--src",
        required=True,
        help="External source checkout directory",
    )
    parser.add_argument(
        "--check-existing",
        action="store_true",
        help="Validate existing checkout remotes",
    )
    parser.add_argument(
        "--write-inventory",
        help="Write a TSV inventory of repositories and checked out commits",
    )
    args = parser.parse_args()

    try:
        repositories = load_manifest(args.manifest)
    except Exception as error:
        print(f"Manifest validation failed: {error}", file=sys.stderr)
        return 2

    errors = validate_manifest(repositories)
    warnings = []

    src_dir = Path(args.src)
    if args.check_existing:
        existing_errors, existing_warnings = check_existing_checkout(
            src_dir,
            repositories,
        )
        errors.extend(existing_errors)
        warnings.extend(existing_warnings)

    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if args.write_inventory:
        write_inventory(args.write_inventory, src_dir, repositories)
        print(f"Wrote source inventory: {args.write_inventory}")

    print(f"Manifest OK: {len(repositories)} repositories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
