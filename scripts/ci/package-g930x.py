#!/usr/bin/env python3
"""Package the kernel and Samsung DT table for the G930X EylemROM ramdisk."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[2]
out = root / 'artifacts'
ak3 = Path(os.environ['ANYKERNEL3_DIR'])
ak3_commit = '41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1'
if subprocess.check_output(['git', '-C', ak3, 'rev-parse', 'HEAD'], text=True).strip() != ak3_commit:
    raise SystemExit('Wrong AnyKernel3 revision')

image = root / 'arch/arm64/boot/Image'
dtb = image.with_name('dtb.img')
with image.open('rb') as stream:
    stream.seek(56)
    if stream.read(4) != b'ARM\x64':
        raise SystemExit('Build output is missing the arm64 Image magic')
if dtb.read_bytes()[:4] != b'DTBH':
    raise SystemExit('Build output is missing the Samsung DT table')

revision = subprocess.check_output(['git', '-C', root, 'rev-parse', 'HEAD'], text=True).strip()
archive = out / f'HeroGrace-G930X-Eylem-KSUN33355-{revision[:12]}.zip'
with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as zip_file:
    for folder in ('META-INF', 'tools'):
        for path in sorted((ak3 / folder).rglob('*')):
            if path.is_file():
                zip_file.write(path, path.relative_to(ak3))
    for path in sorted(ak3.glob('LICENSE*')):
        zip_file.write(path, path.name)
    zip_file.write(root / 'scripts/ci/anykernel.sh', 'anykernel.sh')
    zip_file.write(image, 'Image')
    zip_file.write(dtb, 'dt')
with ZipFile(archive) as zip_file:
    if zip_file.testzip() is not None:
        raise SystemExit('Kernel ZIP CRC check failed')

tool = out / 'ksu_susfs'
cross = os.environ['CROSS_COMPILE']
subprocess.run([cross + 'gcc', '-std=gnu99', '-static', '-O2', '-s', str(root / 'tools/susfs/main.c'), '-o', tool], check=True)
if 'INTERP' in subprocess.check_output([cross + 'readelf', '-l', tool], text=True):
    raise SystemExit('SUSFS CLI must be statically linked')

module = out / 'HeroGrace-SUSFS155-Tools.zip'
with ZipFile(module, 'w', compression=ZIP_DEFLATED) as zip_file:
    zip_file.write(tool, 'ksu_susfs')
    for path in sorted((root / 'tools/susfs/module').iterdir()):
        zip_file.write(path, path.name)
tool.unlink()

manifest = {
    'kernel_commit': revision,
    'hero_grace_base': 'ec7b697b429e9f1372082ce74ceebae411f0caf9',
    'device': 'Exynos Galaxy S7 flat (herolte, G930F/S/L/K)',
    'rom': 'EylemROM V1.0, One UI 5.1, Android 13',
    'kernelsu_legacy_source': 'e3292239f3b8384cc52bdc6f23995d643271a7ce',
    'manager_release': 'https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/v3.4.2',
    'manager_version_code': 33355,
    'manager_uapi_version': 5,
    'susfs_version': 'v1.5.5',
    'susfs_backport': 'https://github.com/ctl4100wl/Cronos_8890/commit/04fff235b743c2e00d89ed08d82a76f84a496dde',
    'anykernel3_commit': ak3_commit,
    'selinux_configuration': 'permissive, matching the reference EylemROM boot image',
    'hardware_tested': False,
}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with (out / 'SHA256SUMS').open('w') as sums:
    for path in (archive, module, out / 'kernel.config', out / 'manifest.json'):
        sums.write(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n')
