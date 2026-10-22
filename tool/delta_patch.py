"""Bounded copy/insert deltas for exact, already-signed APK bytes.

No recompression or re-signing of APK members occurs. ZIP member boundaries
anchor matching blocks so unchanged libraries survive archive offset changes.
"""
import gzip
import hashlib
import io
import struct
from pathlib import Path
from zipfile import BadZipFile, ZipFile

MAGIC = b'SOADLT01'
MAX_APK = 250 * 1024 * 1024
MAX_COPY = 4 * 1024 * 1024
MAX_INSERT = 1024 * 1024
HEADER = struct.Struct('<8sQQ32s32s')


def regions(data):
    """Partition raw archive bytes; all gaps, metadata and signatures survive."""
    boundaries = {0, len(data)}
    try:
        with ZipFile(io.BytesIO(data)) as archive:
            for entry in archive.infolist():
                offset = entry.header_offset
                name, extra = struct.unpack_from('<HH', data, offset + 26)
                start = offset + 30 + name + extra
                end = start + entry.compress_size
                if not 0 <= start <= end <= len(data):
                    raise ValueError('Invalid ZIP member bounds')
                boundaries.update((start, end))
    except BadZipFile:
        pass  # Small synthetic fixtures may be arbitrary byte streams.
    edges = sorted(boundaries)
    return zip(edges, edges[1:])


def chunks(data, block_size):
    for start, end in regions(data):
        for offset in range(start, end, block_size):
            yield offset, data[offset:min(offset + block_size, end)]


def create_patch(base, target, output, *, block_size=16384):
    base, target = Path(base).read_bytes(), Path(target).read_bytes()
    if not 0 < len(base) <= MAX_APK or not 0 < len(target) <= MAX_APK:
        raise ValueError('APK size outside supported range')
    if not 64 <= block_size <= MAX_INSERT:
        raise ValueError('Invalid block size')
    index = {}
    for offset, block in chunks(base, block_size):
        if len(block) >= 64:
            index.setdefault(hashlib.sha256(block).digest(), (offset, len(block)))
    operations = io.BytesIO()
    insert = bytearray()
    copy_offset, copy_length = 0, 0

    def flush_insert():
        if insert:
            operations.write(b'\x01' + struct.pack('<I', len(insert)) + insert)
            insert.clear()

    def flush_copy():
        nonlocal copy_length
        if copy_length:
            operations.write(b'\x00' + struct.pack('<QI', copy_offset, copy_length))
            copy_length = 0

    for _, block in chunks(target, block_size):
        match = index.get(hashlib.sha256(block).digest())
        if match is not None and base[match[0]:match[0] + match[1]] == block:
            flush_insert()
            offset, length = match
            if copy_length and (offset != copy_offset + copy_length or copy_length + length > MAX_COPY):
                flush_copy()
            if not copy_length:
                copy_offset = offset
            copy_length += length
        else:
            flush_copy()
            if len(insert) + len(block) > MAX_INSERT:
                flush_insert()
            insert.extend(block)
    flush_copy()
    flush_insert()
    operations.write(b'\xff')
    header = HEADER.pack(MAGIC, len(base), len(target), hashlib.sha256(base).digest(),
                         hashlib.sha256(target).digest())
    Path(output).write_bytes(header + gzip.compress(operations.getvalue(), compresslevel=9, mtime=0))


def apply_patch(base, patch, output):
    """Host-side verification; the mobile implementation also streams output."""
    base = Path(base).read_bytes()
    patch = Path(patch).read_bytes()
    magic, base_size, target_size, base_hash, target_hash = HEADER.unpack(patch[:HEADER.size])
    if (magic != MAGIC or base_size != len(base) or hashlib.sha256(base).digest() != base_hash
            or not 0 < target_size <= MAX_APK):
        raise ValueError('Delta base/header mismatch')
    result = bytearray()
    with gzip.GzipFile(fileobj=io.BytesIO(patch[HEADER.size:])) as stream:
        def exact(size):
            value = stream.read(size)
            if len(value) != size:
                raise ValueError('Truncated delta')
            return value
        while True:
            opcode = exact(1)[0]
            if opcode == 255:
                if stream.read(1):
                    raise ValueError('Trailing delta commands')
                break
            if opcode == 0:
                offset, size = struct.unpack('<QI', exact(12))
                if not 0 < size <= MAX_COPY or offset + size > len(base):
                    raise ValueError('Invalid copy bounds')
                block = base[offset:offset + size]
            elif opcode == 1:
                size = struct.unpack('<I', exact(4))[0]
                if not 0 < size <= MAX_INSERT:
                    raise ValueError('Invalid insert size')
                block = exact(size)
            else:
                raise ValueError('Unknown delta opcode')
            if len(result) + len(block) > target_size:
                raise ValueError('Delta output too large')
            result.extend(block)
    if len(result) != target_size or hashlib.sha256(result).digest() != target_hash:
        raise ValueError('Delta target mismatch')
    Path(output).write_bytes(result)
