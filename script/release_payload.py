"""Read release versions from payload contents, without executing installers."""
import plistlib
import struct
import zipfile


def windows_version(payload):
    data = payload.read_bytes()

    def unpack(fmt, offset):
        size = struct.calcsize(fmt)
        if offset < 0 or offset + size > len(data):
            raise ValueError('Truncated Windows executable')
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b'MZ':
        raise ValueError('Expected a Windows executable')
    pe, = unpack('<I', 60)
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Invalid PE signature')
    sections, = unpack('<H', pe + 6)
    optional_size, = unpack('<H', pe + 20)
    optional = pe + 24
    magic, = unpack('<H', optional)
    directory = {0x10b: 96, 0x20b: 112}.get(magic)
    if directory is None or optional_size < directory + 24:
        raise ValueError('Missing PE resource directory')
    resource_rva, resource_size = unpack('<II', optional + directory + 16)
    if not resource_rva or not resource_size:
        raise ValueError('Missing Windows version resource')
    section_table = optional + optional_size

    def file_offset(rva, size):
        for i in range(sections):
            _, address, raw_size, raw = unpack('<IIII', section_table + i * 40 + 8)
            delta = rva - address
            if delta >= 0 and delta + size <= raw_size and raw + delta + size <= len(data):
                return raw + delta
        raise ValueError('Invalid PE resource address')

    root = file_offset(resource_rva, resource_size)

    def entries(offset):
        if offset < 0 or offset + 16 > resource_size:
            raise ValueError('Invalid PE resource directory')
        named, ids = unpack('<HH', root + offset + 12)
        if offset + 16 + (named + ids) * 8 > resource_size:
            raise ValueError('Truncated PE resource entries')
        return [unpack('<II', root + offset + 16 + i * 8) for i in range(named + ids)]

    versions = set()
    for kind, names in entries(0):
        if kind != 16:  # RT_VERSION, not an arbitrary signature elsewhere in the EXE.
            continue
        if not names & 0x80000000:
            raise ValueError('Invalid version resource tree')
        for _, languages in entries(names & 0x7fffffff):
            if not languages & 0x80000000:
                raise ValueError('Invalid version language directory')
            for _, leaf in entries(languages & 0x7fffffff):
                if leaf & 0x80000000 or leaf + 16 > resource_size:
                    raise ValueError('Invalid version resource leaf')
                rva, size = unpack('<II', root + leaf)
                start = file_offset(rva, size)
                length, value_size, value_type = unpack('<HHH', start)
                key = 'VS_VERSION_INFO\0'.encode('utf-16le')
                value = (6 + len(key) + 3) & ~3
                if (length > size or length < value + 52 or value_size != 52 or value_type != 0
                        or data[start + 6:start + 6 + len(key)] != key):
                    raise ValueError('Invalid VS_VERSION_INFO')
                signature, _, ms, ls = unpack('<IIII', start + value)
                if signature != 0xfeef04bd:
                    raise ValueError('Invalid fixed version information')
                versions.add((ms >> 16, ms & 65535, ls >> 16, ls & 65535))
    if len(versions) != 1:
        raise ValueError('Missing or inconsistent Windows file versions')
    return versions.pop()


def validate_payload(payload, platform, version, build):
    expected = tuple(map(int, version.split('.'))) + (int(build),)
    if platform == 'macos':
        with zipfile.ZipFile(payload) as archive:
            for name in ['ARose.app/Contents/Info.plist',
                         'ARose.app/Contents/PlugIns/ARoseExtension.appex/Contents/Info.plist']:
                info = plistlib.loads(archive.read(name))
                if (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (version, build):
                    raise ValueError(f'Rebuild {payload.name}: {name} version/build mismatch')
    elif platform == 'windows':
        if windows_version(payload) != expected:
            raise ValueError(f'Rebuild {payload.name}: installer version/build mismatch')
    else:
        raise ValueError('Unsupported update platform')
