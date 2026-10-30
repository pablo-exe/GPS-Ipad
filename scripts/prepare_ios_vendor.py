"""Download Locus' exact arm64 iOS FFI build. No Rust toolchain or 95 MB blob in Git."""
from pathlib import Path
import hashlib
import urllib.request

LOCUS_COMMIT = "83c8fb324983728e8f44759cfd834dc637ee38b5"
FILES = {
    "idevice.h": "23b7a97ed37ebd9bc53e7620b9da8a9d1b5961f05252201462b7c5bd39e0fcc0",
    "libidevice_ffi.a": "05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575",
    "module.modulemap": "d98e25796e1135d892d81e6922a61e78e82b3d6c33322112e9eca1e089c7a300",
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
