#!/usr/bin/env python3
import argparse
import re
import struct
import sys
import zipfile
import zlib

TARGETS = (
    "Lio/flutter/plugins/GeneratedPluginRegistrant;",
    "Lio/flutter/plugins/webviewflutter/WebViewFlutterPlugin;",
)
TARGET_BYTES = {target.encode("ascii") for target in TARGETS}
DEX_ENTRY_RE = re.compile(r"classes(?:(\d+))?\.dex\Z")


class DexError(Exception):
    pass


def _u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def _uleb128(data, offset):
    value = 0
    shift = 0
    for _ in range(5):
        if offset >= len(data):
            raise DexError("truncated ULEB128 string length")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
    raise DexError("invalid ULEB128 string length")


def _check_table(data, label, offset, count, width):
    if count == 0:
        return
    if offset < 0x70 or offset + count * width > len(data):
        raise DexError(f"{label} table is out of bounds")


def _string_bytes(data, offset):
    if offset < 0 or offset >= len(data):
        raise DexError("string data offset is out of bounds")
    _utf16_length, position = _uleb128(data, offset)
    end = data.find(b"\x00", position)
    if end < 0:
        raise DexError("unterminated string data")
    return data[position:end]


def _scan_dex(data):
    if len(data) < 0x70 or data[:4] != b"dex\n" or data[7] != 0:
        raise DexError("not a valid DEX file")

    string_ids_size = _u32(data, 56)
    string_ids_off = _u32(data, 60)
    type_ids_size = _u32(data, 64)
    type_ids_off = _u32(data, 68)
    class_defs_size = _u32(data, 96)
    class_defs_off = _u32(data, 100)

    _check_table(data, "string_ids", string_ids_off, string_ids_size, 4)
    _check_table(data, "type_ids", type_ids_off, type_ids_size, 4)
    _check_table(data, "class_defs", class_defs_off, class_defs_size, 32)

    found = set()
    for index in range(class_defs_size):
        class_def_off = class_defs_off + index * 32
        class_idx = _u32(data, class_def_off)
        if class_idx >= type_ids_size:
            raise DexError("class definition has invalid type index")
        descriptor_idx = _u32(data, type_ids_off + class_idx * 4)
        if descriptor_idx >= string_ids_size:
            raise DexError("type has invalid descriptor string index")
        string_data_off = _u32(data, string_ids_off + descriptor_idx * 4)
        descriptor = _string_bytes(data, string_data_off)
        if descriptor in TARGET_BYTES:
            found.add(descriptor)
    return found


def _dex_entries(zf):
    entries = []
    for info in zf.infolist():
        name = info.filename
        if "/" in name or "\\" in name:
            continue
        match = DEX_ENTRY_RE.fullmatch(name)
        if match is None:
            continue
        number = int(match.group(1)) if match.group(1) is not None else 1
        entries.append((number, name, info))
    entries.sort(key=lambda item: (item[0], item[1]))
    return [(name, info) for _, name, info in entries]


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Check an APK's DEX files for required Flutter plugin classes."
    )
    parser.add_argument("apk", help="path to a debug Flutter APK")
    args = parser.parse_args(argv)

    try:
        archive = zipfile.ZipFile(args.apk)
    except zipfile.BadZipFile:
        print(f"error: not a valid ZIP/APK file: {args.apk}", file=sys.stderr)
        return 2
    except (OSError, ValueError, zipfile.LargeZipFile) as exc:
        print(f"error: cannot open {args.apk}: {exc}", file=sys.stderr)
        return 2

    try:
        with archive:
            entries = _dex_entries(archive)
            if not entries:
                print(
                    f"error: no classes.dex or classesN.dex entries found in {args.apk}",
                    file=sys.stderr,
                )
                return 2

            found = {target: [] for target in TARGETS}
            for name, info in entries:
                try:
                    data = archive.read(info)
                except (
                    OSError,
                    RuntimeError,
                    NotImplementedError,
                    EOFError,
                    zipfile.BadZipFile,
                    zlib.error,
                ) as exc:
                    print(
                        f"error: cannot read {name} from {args.apk}: {exc}",
                        file=sys.stderr,
                    )
                    return 2
                try:
                    matches = _scan_dex(data)
                except DexError as exc:
                    print(f"error: {name}: {exc}", file=sys.stderr)
                    return 2
                for descriptor in matches:
                    found[descriptor.decode("ascii")].append(name)
    except (zipfile.BadZipFile, OSError, RuntimeError, NotImplementedError, EOFError, zlib.error) as exc:
        print(f"error: cannot read {args.apk}: {exc}", file=sys.stderr)
        return 2

    dex_names = [name for name, _ in entries]
    print(f"APK: {args.apk}")
    print(f"DEX files scanned ({len(dex_names)}): {', '.join(dex_names)}")

    missing = []
    for target in TARGETS:
        locations = found[target]
        if locations:
            print(f"FOUND {target} in {', '.join(locations)}")
        else:
            print(f"MISSING {target}")
            missing.append(target)

    if missing:
        print(
            "error: required class definition(s) not found: " + ", ".join(missing),
            file=sys.stderr,
        )
        return 1

    print("OK: all required class definitions found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
