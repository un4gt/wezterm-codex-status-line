from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str], env: dict[str, str]) -> None:
    print(f"\n> {' '.join(command)}", flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic status-line lifecycle tests.")
    parser.add_argument("--log", type=Path, help="Analyze a WezTerm debug log after the tests")
    args = parser.parse_args()

    npx = shutil.which("npx")
    if not npx:
        parser.error("npx was not found on PATH")

    env = os.environ.copy()
    env["npm_config_cache"] = str(ROOT / ".npm-cache")
    run([sys.executable, "-m", "unittest", "tests.test_lifecycle_log", "-v"], env)
    for test in (
        "tests/core_test.lua",
        "tests/statusline_lifecycle_test.lua",
        "tests/statusline_scenario_test.lua",
        "tests/statusline_resume_test.lua",
    ):
        run([npx, "--yes", "--package=fengari-node-cli", "fengari", test], env)

    if args.log:
        run([sys.executable, "scripts/analyze_lifecycle_log.py", str(args.log)], env)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
