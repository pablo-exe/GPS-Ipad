"""Download Locus' exact arm64 iOS FFI build. No Rust toolchain or 95 MB blob in Git."""
from pathlib import Path
import hashlib
import urllib.request

LOCUS_COMMIT = "83c8fb324983728e8f44759cfd834dc637ee38b5"
FILES = {
    "idevice.h": "7b6104244863e1648073117a64a199441865be038f0dfa468f9fc6361649ea18",
    "libidevice_ffi.a": "05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575",
    "module.modulemap": "6140333a8a6d6635e58dc4e4d360b5f68a3aef94850ebca87ca0cfffefc3eaa4",
}


def prepare():
    target = Path(__file__).resolve().parents[1] / "ios" / "Vendor" / "idevice"
    target.mkdir(parents=True, exist_ok=True)
    for name, expected in FILES.items():
        destination = target / name
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
            print(f"Verified {name}")
            continue
        url = f"https://raw.githubusercontent.com/ChrisMack32/Locus/{LOCUS_COMMIT}/Vendor/idevice/{name}"
        temporary = destination.with_suffix(destination.suffix + ".download")
        digest = hashlib.sha256()
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
                digest.update(chunk)
        if digest.hexdigest() != expected:
            temporary.unlink()
            raise RuntimeError(f"SHA-256 mismatch: {name}")
        temporary.replace(destination)
        print(f"Downloaded and verified {name}")


if __name__ == "__main__":
    prepare()
