"""Build (or --check) dist/VoidMarkHealer.zip from the addon files listed in the TOC."""
from pathlib import Path
import argparse, zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = 'VoidMarkHealer'
toc = ROOT / f'{ADDON}.toc'
names = [l.strip().replace('\\', '/') for l in toc.read_text().splitlines() if l.strip() and not l.startswith('#')]
files = {f'{ADDON}/{ADDON}.toc': toc}
for n in names:
    files[f'{ADDON}/{n}'] = ROOT / n
files[f'{ADDON}/README.md'] = ROOT / 'README.md'

def contents(p):
    return p.read_bytes().replace(b'\r\n', b'\n')

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--check', action='store_true')
args = ap.parse_args()
archive = ROOT / 'dist' / f'{ADDON}.zip'
if not args.check:
    archive.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, path in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, contents(path))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None, 'ZIP integrity failure'
    assert set(z.namelist()) == set(files), 'ZIP file list differs from TOC'
    for name, path in files.items():
        assert z.read(name) == contents(path), 'Stale ZIP entry: ' + name
print(f'PASS: {len(files)} files packaged and verified: dist/{archive.name}')
