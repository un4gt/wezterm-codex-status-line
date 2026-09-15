from __future__ import annotations

import tarfile
import zipfile
from pathlib import Path
from collections.abc import Callable


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "codex_statusline.lua",
    "codex_statusline_core.lua",
    "codex_statusline_bridge.js",
    "codex_statusline_bridge.ps1",
    "codex_statusline_bridge.py",
    "install.ps1",
    "contract/config.schema.json",
    "contract/default-config.json",
    "contract/render-cases.json",
    "contract/sample-state.json",
    "contract/model-pricing.json",
    "contract/usage-cases.json",
}
REQUIRED.update(path.relative_to(ROOT).as_posix() for path in (ROOT / "codex_statusline").rglob("*.lua"))


def one(pattern: str) -> Path:
    matches = sorted(ROOT.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(f"Expected one {pattern} archive, found {len(matches)}")
    return matches[0]


def verify(path: Path, members: list[str], read: Callable[[str], bytes]) -> None:
    normalized = {name.replace("\\", "/") for name in members}
    missing = sorted(
        required
        for required in REQUIRED
        if not any(name.endswith(f"/assets/{required}") for name in normalized)
    )
    if missing:
        raise SystemExit(f"{path.name} is missing packaged assets: {', '.join(missing)}")
    for required in REQUIRED:
        member = next(name for name in members if name.replace("\\", "/").endswith(f"/assets/{required}"))
        if read(member) != (ROOT / required).read_bytes():
            raise SystemExit(f"{path.name}: asset differs from source: {required}")
    license_suffix, license_depth = (
        (".dist-info/licenses/LICENSE", 2) if path.suffix == ".whl" else ("/LICENSE", 1)
    )
    license_members = [
        name
        for name in members
        if name.replace("\\", "/").endswith(license_suffix)
        and name.replace("\\", "/").count("/") == license_depth
    ]
    if len(license_members) != 1:
        raise SystemExit(f"{path.name}: expected one distribution LICENSE, found {len(license_members)}")
    if read(license_members[0]) != (ROOT / "LICENSE").read_bytes():
        raise SystemExit(f"{path.name}: LICENSE differs from source")
    print(f"{path.name}: {len(REQUIRED)} required assets and MIT LICENSE match source")


def main() -> None:
    npm = one("packages/npm/*.tgz")
    wheel = one("packages/python/dist/*.whl")
    sdist = one("packages/python/dist/*.tar.gz")
    with tarfile.open(npm, "r:gz") as archive:
        verify(npm, archive.getnames(), lambda name: archive.extractfile(name).read())
    with zipfile.ZipFile(wheel) as archive:
        verify(wheel, archive.namelist(), archive.read)
    with tarfile.open(sdist, "r:gz") as archive:
        verify(sdist, archive.getnames(), lambda name: archive.extractfile(name).read())


if __name__ == "__main__":
    main()
