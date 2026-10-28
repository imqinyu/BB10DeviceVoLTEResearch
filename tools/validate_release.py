#!/usr/bin/env python3
"""Validate the publication tree, nested distributions and optional checksum list.

This is a conservative automated check, not a substitute for human review.
Standard library only. No network/device access and no code execution.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile

SKIP_DIRS = {'.git', '__pycache__', 'build'}
VENDOR_BINARIES = {'ims_rrm', 'io-pkt-v6-hc', 'io-bb', 'devnp-sbgse_drv.so',
                   'libvpn_adapter_ims.so.1'}
PRIVATE_KEY = re.compile(rb'-----BEGIN (?:[A-Z0-9 ]+)?PRIVATE KEY-----\s*\r?\n[A-Za-z0-9+/=]{32,}')
SUBSCRIBER_LINE = re.compile(rb'(?im)^(?:\[n\])?(?:imsi|iccid|imei|pin64|meid|deviceserialnumber)::?[^\r\n]{4,}')
PERSONAL_PATH = re.compile(rb'(?i)[A-Z]:[/\\]Users[/\\](?!PUBLIC(?:[/\\]|$)|YOUR[-_ ]?USER(?:[/\\]|$))[^/\\\r\n"<>]+[/\\]')
PHONE = re.compile(rb'(?<![0-9A-Fa-f])(?:\+?86[- ]?)?1[3-9][0-9]{9}(?![0-9A-Fa-f])')
IDENTITY_XML = re.compile(rb'(?i)<(?:IMSI|ICCID|IMEI|PrivateUserIdentity|PublicUserIdentity)>[^<]*[0-9]{8,}[^<]*</')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check_content(label, data, errors):
    for name, pattern in [('private key', PRIVATE_KEY), ('subscriber/device identity', SUBSCRIBER_LINE),
                          ('personal workstation path', PERSONAL_PATH), ('mobile number', PHONE),
                          ('subscriber XML', IDENTITY_XML)]:
        if pattern.search(data):
            errors.append(f'{label}: possible {name}; review required')


def check_name(label, errors):
    basename = PurePosixPath(label.replace('\\', '/')).name.lower()
    if basename in VENDOR_BINARIES or basename.startswith(('id_rsa', 'bb_root_key', 'known_hosts')):
        errors.append(f'{label}: disallowed private/vendor filename')
    if basename.endswith(('.pem', '.ppk', '.key', '.tar', '.pcap', '.pcapng', '.i64', '.idb', '.log')):
        errors.append(f'{label}: raw/private artifact type is not allowed in this release')


def check_zip(label, data, errors, depth=0):
    if depth > 2:
        errors.append(f'{label}: nested archive depth exceeds review limit')
        return
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if archive.testzip() is not None:
                errors.append(f'{label}: ZIP CRC failure')
            names = set(archive.namelist())
            for info in archive.infolist():
                path = PurePosixPath(info.filename.replace('\\', '/'))
                if path.is_absolute() or '..' in path.parts:
                    errors.append(f'{label}: unsafe archive member path')
                if info.is_dir():
                    continue
                payload = archive.read(info)
                member_label = f'{label}!{info.filename}'
                check_name(member_label, errors)
                check_content(member_label, payload, errors)
                if info.filename.lower().endswith('.zip'):
                    check_zip(member_label, payload, errors, depth + 1)
            for filename in names:
                if filename.endswith('/SHA256.json'):
                    base = filename.rsplit('/', 1)[0] + '/'
                    manifest = json.loads(archive.read(filename).decode('utf-8-sig'))
                    for relative, expected in manifest.items():
                        member = base + relative.replace('\\', '/')
                        if member not in names or digest(archive.read(member)).lower() != expected.lower():
                            errors.append(f'{label}: distribution component hash mismatch: {relative}')
    except (zipfile.BadZipFile, KeyError, UnicodeError, json.JSONDecodeError) as error:
        errors.append(f'{label}: archive validation failed ({type(error).__name__})')


def public_files(root):
    return sorted(p for p in root.rglob('*') if p.is_file()
                  and not any(part in SKIP_DIRS for part in p.relative_to(root).parts))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--write-manifest', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    errors = []
    files = public_files(root)
    for path in files:
        relative = path.relative_to(root).as_posix()
        check_name(relative, errors)
        data = path.read_bytes()
        check_content(relative, data, errors)
        if path.suffix.lower() == '.zip':
            check_zip(relative, data, errors)

    # Check local links in the new handoff documentation, not in preserved variants.
    docs = list(root.glob('*.md'))
    docs += list((root / 'docs').glob('*.md'))
    docs += list((root / 'experiments').rglob('*.md'))
    for path in docs:
        if not path.exists():
            errors.append(f'missing document: {path.name}')
            continue
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8-sig')):
            if target.startswith(('https://', 'http://', '#', 'mailto:')):
                continue
            local = target.split('#', 1)[0]
            if local and not (path.parent / local).exists():
                errors.append(f'{path.relative_to(root)}: broken link: {local}')

    # Provenance hashes identify original ZIPs; extracted variants must match them.
    for item in json.loads((root / 'provenance.json').read_text(encoding='utf-8')):
        archive_path = root / item['archive']
        if digest(archive_path.read_bytes()) != item['sha256']:
            errors.append(f'{item["archive"]}: original archive provenance mismatch')
        with zipfile.ZipFile(archive_path) as archive:
            for path in (root / 'variants' / item['profile']).rglob('*'):
                if not path.is_file():
                    continue
                relative = path.relative_to(root / 'variants' / item['profile']).as_posix()
                matches = [name for name in archive.namelist() if name.split('/', 1)[-1] == relative]
                if len(matches) != 1 or path.read_bytes() != archive.read(matches[0]):
                    errors.append(f'variant differs from supplied snapshot: {item["profile"]}/{relative}')

    manifest_path = root / 'MANIFEST.sha256'
    expected_text = ''.join(f'{digest(p.read_bytes())}  {p.relative_to(root).as_posix()}\n'
                            for p in files if p != manifest_path)
    if args.write_manifest and not errors:
        manifest_path.write_text(expected_text, encoding='utf-8', newline='\n')
    elif manifest_path.exists() and manifest_path.read_text(encoding='utf-8') != expected_text:
        errors.append('MANIFEST.sha256 does not match the publication tree')
    if errors:
        print('\n'.join('ERROR: ' + error for error in errors), file=sys.stderr)
        return 1
    print(f'PASS: {len(files)} public files; nested ZIPs, distribution hashes, privacy patterns, local links and provenance checked.')
    if not manifest_path.exists():
        print('No checksum list yet. Use --write-manifest to create it.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
