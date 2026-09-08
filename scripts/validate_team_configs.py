#!/usr/bin/env python3
"""Repo-level validation of team configuration files.

Two checks that isolated Terraform states cannot perform, because each
stack only sees one (team, environment) cell:

1. Schema conformance: every teams/<team>/<env>.yaml validates against
   schema/schema.json.
2. Bucket name uniqueness: bucket names are team-agnostic by design
   (<environment>-<name>, ownership-transferable), so two teams claiming
   the same name in one environment would collide at apply time
   (BucketAlreadyExists). This gate catches the collision at PR time,
   where the repo-wide view exists.

Exits non-zero with a message on the first failure found.
"""

import json
import re
import sys
from pathlib import Path

import jsonschema
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
TEAMS_DIR = REPO_ROOT / "teams"
ENV_FILE_PATTERN = re.compile(r"^[a-z0-9-]+$")


def load_team_files():
    """Yield (team, environment, path, config) for every team env file."""
    for team_path in sorted(TEAMS_DIR.iterdir()):
        if not team_path.is_dir():
            continue
        team = team_path.name
        for env_file in sorted(team_path.glob("*.yaml")):
            environment = env_file.stem
            if not ENV_FILE_PATTERN.match(environment):
                continue
            with open(env_file) as f:
                config = yaml.safe_load(f)
            yield team, environment, env_file, config


def validate_schema(configs, schema):
    failures = []
    for team, environment, path, config in configs:
        try:
            jsonschema.validate(config, schema)
        except jsonschema.ValidationError as e:
            failures.append(
                f"{path.relative_to(REPO_ROOT)}: schema violation at "
                f"{list(e.absolute_path)}: {e.message}"
            )
    return failures


def validate_bucket_uniqueness(configs):
    """Fail if two teams declare the same bucket name in one environment.

    The physical bucket is <environment>-<name> (see module/s3), so the
    collision key is (environment, name) across teams.
    """
    claims = {}
    failures = []
    for team, environment, path, config in configs:
        for bucket in config.get("s3", {}).get("buckets", []):
            key = (environment, bucket["name"])
            claims.setdefault(key, []).append(team)
    for (environment, name), teams in sorted(claims.items()):
        if len(teams) > 1:
            failures.append(
                f"bucket '{name}' is declared by multiple teams in "
                f"environment '{environment}': {', '.join(teams)} "
                f"(physical bucket '{environment}-{name}' would collide)"
            )
    return failures


def main():
    schema = json.loads((REPO_ROOT / "schema" / "schema.json").read_text())
    configs = list(load_team_files())
    if not configs:
        print("error: no team config files found", file=sys.stderr)
        return 1

    failures = validate_schema(configs, schema)
    failures += validate_bucket_uniqueness(configs)

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        print(f"{len(failures)} validation failure(s)", file=sys.stderr)
        return 1

    teams = {team for team, _, _, _ in configs}
    print(
        f"ok: {len(teams)} teams ({len(configs)} config files) valid; "
        f"bucket names unique per environment"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())