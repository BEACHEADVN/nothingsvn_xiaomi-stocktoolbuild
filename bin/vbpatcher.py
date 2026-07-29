import os
import struct
import json
import argparse
import sys

try:
    import lz4.frame
    import lz4.block
except ImportError:
    print("Error: 'lz4' module not found.")
    print("Please install it using: pip install lz4")
    sys.exit(1)

try:
    import zstandard as zstd

    HAS_ZSTD = True
except ImportError:
    HAS_ZSTD = False

MAGIC = b"VNDRBOOT"
V3_FMT = "<8s I I I I I 2048s I 16s I I Q"
V4_EXT_FMT = "<I I I I"


def read_padded(f, size, page_size):
    data = f.read(size)
    padding_size = (page_size - (size % page_size)) % page_size
    if padding_size > 0:
        f.read(padding_size)
    return data


def write_padded(f, data, page_size):
    f.write(data)
    padding_size = (page_size - (len(data) % page_size)) % page_size
    if padding_size > 0:
        f.write(b"\x00" * padding_size)


def decompress_ramdisk(data):
    magic = data[:4]
    if magic == b"\x04\x22\x4d\x18":
        print("> Detected compression: LZ4")
        return "lz4_frame", lz4.frame.decompress(data)
    elif magic == b"\x02\x21\x4c\x18":
        print("> Detected compression: LZ4 Legacy")
        offset = 4
        out = bytearray()
        while offset < len(data):
            if offset + 4 > len(data):
                break
            comp_size = struct.unpack("<I", data[offset : offset + 4])[0]
            offset += 4
            if offset + comp_size > len(data):
                break
            chunk = data[offset : offset + comp_size]
            out.extend(lz4.block.decompress(chunk, uncompressed_size=8388608))
            offset += comp_size
        return "lz4_legacy", bytes(out)
    elif magic == b"\x28\xb5\x2f\xfd":
        print("> Detected compression: ZSTD")
        if not HAS_ZSTD:
            raise Exception("Zstandard module missing. Run: pip install zstandard")
        return "zstd", zstd.ZstdDecompressor().decompress(data)
    elif magic[:2] == b"\x1f\x8b":
        import gzip

        print("> Detected compression: GZIP")
        return "gzip", gzip.decompress(data)
    elif magic[:4] == b"0707":
        print("> Detected compression: Uncompressed CPIO")
        return "none", data
    else:
        raise Exception(f"Unknown or unsupported ramdisk format (Magic: {magic.hex()})")


def compress_ramdisk(data, fmt):
    if fmt == "lz4_frame":
        return lz4.frame.compress(data)
    elif fmt == "lz4_legacy":
        block_size = 8388608
        out = bytearray(b"\x02\x21\x4c\x18")
        for i in range(0, len(data), block_size):
            chunk = data[i : i + block_size]
            comp_chunk = lz4.block.compress(
                chunk, mode="high_compression", store_size=False
            )
            out.extend(struct.pack("<I", len(comp_chunk)))
            out.extend(comp_chunk)
        return bytes(out)
    elif fmt == "zstd":
        if not HAS_ZSTD:
            raise Exception("Zstandard module missing.")
        return zstd.ZstdCompressor(level=3).compress(data)
    elif fmt == "gzip":
        import gzip

        return gzip.compress(data)
    else:
        return data


def build_cpio_header(ino, mode, uid, gid, filesize, namesize):
    nlink = 2 if (mode & 0xF000) == 0x4000 else 1
    return f"070701{ino:08x}{mode:08x}{uid:08x}{gid:08x}{nlink:08x}00000000{filesize:08x}00000000000000000000000000000000{namesize:08x}00000000".encode(
        "ascii"
    )


def unpack_cpio(data, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    offset = 0
    metadata = []
    while offset < len(data):
        if offset + 110 > len(data):
            break
        header = data[offset : offset + 110].decode("ascii", errors="ignore")
        if not header.startswith("070701"):
            break

        mode = int(header[14:22], 16)
        uid = int(header[22:30], 16)
        gid = int(header[30:38], 16)
        filesize = int(header[54:62], 16)
        namesize = int(header[94:102], 16)

        offset += 110
        name = data[offset : offset + namesize - 1].decode("utf-8", errors="ignore")
        offset += namesize
        offset += (4 - ((110 + namesize) % 4)) % 4
        file_data = data[offset : offset + filesize]
        offset += filesize
        offset += (4 - (filesize % 4)) % 4

        if name == "TRAILER!!!":
            break
        out_path = os.path.join(out_dir, name)
        meta = {"name": name, "mode": mode, "uid": uid, "gid": gid}

        if (mode & 0xF000) == 0x4000:
            os.makedirs(out_path, exist_ok=True)
        elif (mode & 0xF000) == 0xA000:
            meta["symlink_target"] = file_data.decode("utf-8", errors="ignore")
        else:
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "wb") as f:
                f.write(file_data)
        metadata.append(meta)
    with open(os.path.join(out_dir, "ramdisk_meta.json"), "w") as f:
        json.dump(metadata, f, indent=4)


def pack_cpio(in_dir):
    meta_path = os.path.join(in_dir, "ramdisk_meta.json")
    if not os.path.exists(meta_path):
        return b""

    with open(meta_path, "r") as f:
        metadata = json.load(f)
    existing_files = set(m["name"] for m in metadata)
    for root, dirs, files in os.walk(in_dir):
        for name in dirs + files:
            full_path = os.path.join(root, name)
            rel_path = os.path.relpath(full_path, in_dir).replace("\\", "/")
            if rel_path == "ramdisk_meta.json":
                continue
            if rel_path not in existing_files:
                is_dir = os.path.isdir(full_path)
                metadata.append(
                    {
                        "name": rel_path,
                        "mode": 0x41ED if is_dir else 0x81A4,
                        "uid": 0,
                        "gid": 0,
                    }
                )
                existing_files.add(rel_path)
    out_data = bytearray()
    ino = 1
    for meta in metadata:
        name = meta["name"]
        mode = meta["mode"]
        file_path = os.path.join(in_dir, name)
        file_data = b""
        if (mode & 0xF000) == 0x4000:
            pass
        elif (mode & 0xF000) == 0xA000:
            file_data = meta.get("symlink_target", "").encode("utf-8")
        else:
            if os.path.exists(file_path):
                with open(file_path, "rb") as f:
                    file_data = f.read()
            else:
                continue

        filesize = len(file_data)
        name_bytes = name.encode("utf-8") + b"\x00"
        namesize = len(name_bytes)
        out_data.extend(
            build_cpio_header(ino, mode, meta["uid"], meta["gid"], filesize, namesize)
        )
        out_data.extend(name_bytes)
        out_data.extend(b"\x00" * ((4 - ((110 + namesize) % 4)) % 4))
        out_data.extend(file_data)
        out_data.extend(b"\x00" * ((4 - (filesize % 4)) % 4))
        ino += 1

    name_bytes = b"TRAILER!!!\x00"
    namesize = len(name_bytes)
    out_data.extend(build_cpio_header(ino, 0, 0, 0, 0, namesize))
    out_data.extend(name_bytes)
    out_data.extend(b"\x00" * ((4 - ((110 + namesize) % 4)) % 4))
    return bytes(out_data)


def unpack(args):
    out_dir = args.output
    os.makedirs(out_dir, exist_ok=True)

    with open(args.image, "rb") as f:
        f.seek(0, os.SEEK_END)
        original_size = f.tell()
        f.seek(0)

        if f.read(8) != MAGIC:
            return print("Error: Invalid Magic, not a vendor_boot images")
        f.seek(0)
        unpacked = struct.unpack(V3_FMT, f.read(struct.calcsize(V3_FMT)))
        hdr_version, page_size = unpacked[1], unpacked[2]

        config = {
            "original_image_size": original_size,
            "header_version": hdr_version,
            "page_size": page_size,
            "kernel_load_addr": unpacked[3],
            "ramdisk_load_addr": unpacked[4],
            "vendor_ramdisk_size": unpacked[5],
            "cmdline": unpacked[6].split(b"\x00")[0].decode("utf-8", errors="ignore"),
            "tags_load_addr": unpacked[7],
            "name": unpacked[8].split(b"\x00")[0].decode("utf-8", errors="ignore"),
            "header_size": unpacked[9],
            "dtb_size": unpacked[10],
            "dtb_load_addr": unpacked[11],
        }

        if hdr_version == 4:
            v4_unpacked = struct.unpack(V4_EXT_FMT, f.read(struct.calcsize(V4_EXT_FMT)))
            config.update(
                {
                    "vendor_ramdisk_table_size": v4_unpacked[0],
                    "vendor_ramdisk_table_entry_num": v4_unpacked[1],
                    "vendor_ramdisk_table_entry_size": v4_unpacked[2],
                    "bootconfig_size": v4_unpacked[3],
                }
            )

        print(f"> Unpacking vendor_boot V{hdr_version} {original_size} bytes")

        f.seek(original_size - 64)
        footer_data = f.read(64)
        if footer_data.startswith(b"AVBf"):
            print("> Detected AVB Footer. Extracting data...")
            magic, major, minor, orig_size_avb, vbmeta_offset, vbmeta_size = (
                struct.unpack(">4sIIQQQ", footer_data[:36])
            )

            f.seek(vbmeta_offset)
            vbmeta_data = f.read(vbmeta_size)

            with open(os.path.join(out_dir, "avb_vbmeta.img"), "wb") as out:
                out.write(vbmeta_data)
            with open(os.path.join(out_dir, "avb_footer.bin"), "wb") as out:
                out.write(footer_data)
            config["has_avb"] = True
        else:
            config["has_avb"] = False

        f.seek(page_size)
        ramdisk_data = read_padded(f, config["vendor_ramdisk_size"], page_size)
        
        # Đảm bảo ramdisk_root luôn được khởi tạo
        ramdisk_root = os.path.join(out_dir, "ramdisk_root")
        os.makedirs(ramdisk_root, exist_ok=True)

        try:
            print("> Identifying ramdisk compression...")
            fmt, uncompressed = decompress_ramdisk(ramdisk_data)
            config["ramdisk_compression"] = fmt
            unpack_cpio(uncompressed, ramdisk_root)
        except Exception as e:
            print(f"> Cannot extract CPIO automatically: {e}")
            with open(os.path.join(out_dir, "vendor_ramdisk.img"), "wb") as r_out:
                r_out.write(ramdisk_data)

        with open(os.path.join(out_dir, "dtb.img"), "wb") as out:
            out.write(read_padded(f, config["dtb_size"], page_size))
        if hdr_version == 4:
            with open(os.path.join(out_dir, "vendor_ramdisk_table.img"), "wb") as out:
                out.write(
                    read_padded(f, config["vendor_ramdisk_table_size"], page_size)
                )
            with open(os.path.join(out_dir, "bootconfig.img"), "wb") as out:
                out.write(read_padded(f, config["bootconfig_size"], page_size))

        with open(os.path.join(out_dir, "config.json"), "w") as out:
            json.dump(config, out, indent=4)

    print(f"> Ramdisk path: {ramdisk_root}")


def repack(args):
    out_dir = os.path.dirname(args.config)
    with open(args.config, "r") as f:
        config = json.load(f)

    hdr_version, page_size = config["header_version"], config["page_size"]
    fmt = config.get("ramdisk_compression", "lz4_legacy")
    print(f"> Repacking vendor_boot V{hdr_version} with {fmt}...")

    ramdisk_dir = os.path.join(out_dir, "ramdisk_root")
    meta_path = os.path.join(ramdisk_dir, "ramdisk_meta.json")

    if os.path.isdir(ramdisk_dir) and os.path.exists(meta_path):
        print("> Packing CPIO and compressing Ramdisk...")
        uncompressed = pack_cpio(ramdisk_dir)
        ramdisk_data = compress_ramdisk(uncompressed, fmt)
    else:
        print("> Using raw vendor_ramdisk.img...")
        with open(os.path.join(out_dir, "vendor_ramdisk.img"), "rb") as f:
            ramdisk_data = f.read()

    with open(os.path.join(out_dir, "dtb.img"), "rb") as f:
        dtb_data = f.read()

    header_data = struct.pack(
        V3_FMT,
        MAGIC,
        hdr_version,
        page_size,
        config["kernel_load_addr"],
        config["ramdisk_load_addr"],
        len(ramdisk_data),
        config["cmdline"].encode("utf-8")[:2047].ljust(2048, b"\x00"),
        config["tags_load_addr"],
        config["name"].encode("utf-8")[:15].ljust(16, b"\x00"),
        (2128 if hdr_version == 4 else 2112),
        len(dtb_data),
        config["dtb_load_addr"],
    )

    if hdr_version == 4:
        with open(os.path.join(out_dir, "vendor_ramdisk_table.img"), "rb") as f:
            v4_ramdisk_table_data = f.read()
        with open(os.path.join(out_dir, "bootconfig.img"), "rb") as f:
            bootconfig_data = f.read()
        header_data += struct.pack(
            V4_EXT_FMT,
            len(v4_ramdisk_table_data),
            config["vendor_ramdisk_table_entry_num"],
            config["vendor_ramdisk_table_entry_size"],
            len(bootconfig_data),
        )

    with open(args.output, "wb") as f:
        write_padded(f, header_data, page_size)
        write_padded(f, ramdisk_data, page_size)
        write_padded(f, dtb_data, page_size)
        if hdr_version == 4:
            write_padded(f, v4_ramdisk_table_data, page_size)
            write_padded(f, bootconfig_data, page_size)

        new_payload_size = f.tell()
        target_size = config.get("original_image_size", 0)

        if config.get("has_avb", False):
            print("> Updating and re-attaching AVB structures...")
            with open(os.path.join(out_dir, "avb_vbmeta.img"), "rb") as vf:
                vbmeta_data = vf.read()
            with open(os.path.join(out_dir, "avb_footer.bin"), "rb") as ff:
                footer_data = ff.read()

            f.write(vbmeta_data)

            unpacked_avb = list(struct.unpack(">4sIIQQQ", footer_data[:36]))
            unpacked_avb[3] = new_payload_size
            unpacked_avb[4] = new_payload_size

            new_footer = struct.pack(">4sIIQQQ", *unpacked_avb) + footer_data[36:]

            current_size = f.tell()
            pad_len = target_size - 64 - current_size

            if pad_len > 0:
                f.write(b"\x00" * pad_len)
            elif pad_len < 0:
                print(
                    "\n> WARNING: The modified payload is larger than the original partition size."
                )
                print(
                    f"> Target Partition Size: {target_size} bytes. Required Size: {current_size + 64} bytes."
                )

            f.write(new_footer)
        else:
            current_size = f.tell()
            if target_size > current_size:
                f.write(b"\x00" * (target_size - current_size))

    print(f"> Image exported to: {args.output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    p_unpack = subparsers.add_parser("unpack")
    p_unpack.add_argument("-i", "--image", required=True)
    p_unpack.add_argument("-o", "--output", required=True)

    p_repack = subparsers.add_parser("repack")
    p_repack.add_argument("-c", "--config", required=True)
    p_repack.add_argument("-o", "--output", required=True)

    args = parser.parse_args()
    unpack(args) if args.command == "unpack" else repack(args)
