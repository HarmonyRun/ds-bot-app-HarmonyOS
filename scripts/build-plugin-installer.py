"""Bundle the existing, hash-verified release archive without repacking it."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent / "plugin-installer"


def build(archive: Path, output: Path) -> Path:
    release = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
    payload = archive.read_bytes()
    if hashlib.sha256(payload).hexdigest() != release["sha256"]:
        raise ValueError("Release archive checksum mismatch; refusing to build installer")
    entries = {release["archive"]: payload}
    for name in ["release.json", "prepare-plugin.ps1", "prepare-plugin.cmd", "README.txt"]:
        text = (ROOT / name).read_text(encoding="utf-8")
        # Windows PowerShell 5.1 and Notepad need a BOM for non-ASCII paths/text.
        encoding = "utf-8-sig" if name in ["prepare-plugin.ps1", "README.txt"] else "utf-8"
        entries[name] = text.replace("\n", "\r\n").encode(encoding)
    entries["SHA256SUMS.txt"] = "".join(
        f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, data in sorted(entries.items())
    ).encode()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / f'dsbot-plugin-installer-{release["revision"]}.zip'
    # Fixed metadata makes a re-run produce exactly the same downloadable bytes.
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 14, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, data)
    checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / f'SHA256SUMS-installer-{release["revision"]}').write_text(
        f"{checksum}  {destination.name}\n", encoding="utf-8"
    )
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(build(args.archive, args.output))
