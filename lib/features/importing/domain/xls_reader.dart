import 'dart:typed_data';

// Read-only Excel 97-2003 BIFF8/CFB. No macros or formulas are executed.
// Format references: Microsoft MS-CFB 2.2 and MS-XLS 2.4 / 2.5.293.
typedef XlsRows = ({String name, List<List<String>> rows});

List<XlsRows> readXlsRows(Uint8List bytes) {
  try {
    return _BiffWorkbook(_CompoundFile(bytes).workbook()).read();
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('XLS 文件结构损坏，请用 Excel 或 WPS 重新保存后导入');
  }
}

Never _invalid() => throw const FormatException('XLS 文件不完整或结构损坏，请重新保存后导入');
int _u16(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint16(offset, Endian.little);
int _u32(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint32(offset, Endian.little);

class _CompoundFile {
  _CompoundFile(this.bytes) {
    const magic = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
    if (bytes.length < 512 ||
        !List.generate(8, (i) => bytes[i] == magic[i]).every((v) => v)) {
      throw const FormatException(
        '不是有效的 Excel 97–2003 XLS 文件，请重新另存为 .xls 或 .xlsx',
      );
    }
    final major = _u16(bytes, 26), shift = _u16(bytes, 30);
    if (!((major == 3 && shift == 9) || (major == 4 && shift == 12)) ||
        _u16(bytes, 28) != 0xfffe ||
        _u16(bytes, 32) != 6 ||
        _u32(bytes, 56) != 4096) {
      _invalid();
    }
    sectorSize = 1 << shift;
    sectors = bytes.length ~/ sectorSize - 1;
    if (sectors < 1 || bytes.length % sectorSize != 0) _invalid();
    final fatCount = _u32(bytes, 44), difatCount = _u32(bytes, 72);
    if (fatCount > sectors || difatCount > sectors) _invalid();
    final fatIds = <int>[];
    void addFat(int id) {
      if (id == free) return;
      if (id >= sectors || fatIds.length >= fatCount) _invalid();
      fatIds.add(id);
    }

    for (var p = 76; p < 512; p += 4) {
      addFat(_u32(bytes, p));
    }
    var next = _u32(bytes, 68);
    final seen = <int>{};
    for (var i = 0; i < difatCount; i++) {
      if (!seen.add(next)) _invalid();
      final data = sector(next);
      for (var p = 0; p < sectorSize - 4; p += 4) {
        addFat(_u32(data, p));
      }
      next = _u32(data, sectorSize - 4);
    }
    if (fatIds.length != fatCount || fatIds.toSet().length != fatCount) {
      _invalid();
    }
    for (final id in fatIds) {
      final data = sector(id);
      for (var p = 0; p < sectorSize; p += 4) {
        fat.add(_u32(data, p));
      }
    }
    if (fat.length < sectors) _invalid();
  }
  static const end = 0xfffffffe, free = 0xffffffff;
  final Uint8List bytes;
  late final int sectorSize, sectors;
  final fat = <int>[];

  Uint8List sector(int id) {
    if (id < 0 || id >= sectors) _invalid();
    return Uint8List.sublistView(
      bytes,
      (id + 1) * sectorSize,
      (id + 2) * sectorSize,
    );
  }

  Uint8List chain(
    int start,
    List<int> table,
    int blockSize,
    Uint8List Function(int) block, {
    int? size,
  }) {
    if (size == 0) return Uint8List(0);
    if (size != null && (size < 0 || size > bytes.length)) _invalid();
    final builder = BytesBuilder(copy: false), visited = <int>{};
    var current = start;
    while (current != end) {
      if (current < 0 ||
          current >= table.length ||
          !visited.add(current) ||
          builder.length >= bytes.length ||
          (size != null && builder.length >= size)) {
        _invalid();
      }
      builder.add(block(current));
      current = table[current];
    }
    final result = builder.takeBytes();
    if (size == null) return result;
    if (result.length < size || result.length - size >= blockSize) _invalid();
    return Uint8List.sublistView(result, 0, size);
  }

  Uint8List workbook() {
    final directory = chain(_u32(bytes, 48), fat, sectorSize, sector);
    ({int start, int size})? root, book;
    for (var p = 0; p + 128 <= directory.length; p += 128) {
      final type = directory[p + 66];
      if (type == 0) continue;
      final nameLength = _u16(directory, p + 64);
      if (nameLength < 2 || nameLength > 64 || nameLength.isOdd) _invalid();
      final name = String.fromCharCodes([
        for (var c = p; c < p + nameLength - 2; c += 2) _u16(directory, c),
      ]);
      if (name == 'EncryptedPackage' || name == 'EncryptionInfo') {
        throw const FormatException('文件已加密，请移除打开密码后重新导入');
      }
      final size = _u32(directory, p + 120);
      if (_u32(directory, p + 124) != 0) _invalid();
      final entry = (start: _u32(directory, p + 116), size: size);
      if (type == 5) root = entry;
      if (type == 2 && (name == 'Workbook' || name == 'Book')) {
        if (book != null) _invalid();
        book = entry;
      }
    }
    if (book == null || root == null) _invalid();
    if (book.size >= 4096) {
      return chain(book.start, fat, sectorSize, sector, size: book.size);
    }
    final miniStream = chain(
      root.start,
      fat,
      sectorSize,
      sector,
      size: root.size,
    );
    final miniCount = _u32(bytes, 64);
    if (miniCount > sectors) _invalid();
    final miniBytes = chain(
      _u32(bytes, 60),
      fat,
      sectorSize,
      sector,
      size: miniCount * sectorSize,
    );
    final miniFat = [
      for (var p = 0; p < miniBytes.length; p += 4) _u32(miniBytes, p),
    ];
    return chain(book.start, miniFat, 64, (id) {
      if ((id + 1) * 64 > miniStream.length) _invalid();
      return Uint8List.sublistView(miniStream, id * 64, (id + 1) * 64);
    }, size: book.size);
  }
}

class _Record {
  const _Record(this.type, this.data, this.next);
  final int type, next;
  final Uint8List data;
}

class _BiffWorkbook {
  _BiffWorkbook(this.data);
  final Uint8List data;
  final strings = <String>[];

  _Record record(int offset) {
    if (offset < 0 || offset + 4 > data.length) _invalid();
    final length = _u16(data, offset + 2),
        next = offset + 4 + _u16(data, offset + 2);
    if (length > 8224 || next > data.length) _invalid();
    return _Record(
      _u16(data, offset),
      Uint8List.sublistView(data, offset + 4, next),
      next,
    );
  }

  void bof(_Record r, int type) {
    if (r.type != 0x0809 || r.data.length < 4 || _u16(r.data, 0) != 0x0600) {
      throw const FormatException(
        '仅支持 Excel 97–2003 XLS；更早的文件请用 Excel/WPS 另存为 .xlsx',
      );
    }
    if (_u16(r.data, 2) != type) _invalid();
  }

  List<XlsRows> read() {
    bof(record(0), 5);
    final sheets = <({String name, int offset})>[];
    var position = record(0).next;
    var ended = false;
    while (position < data.length) {
      final r = record(position), d = r.data;
      position = r.next;
      if (r.type == 0x000a) {
        ended = true;
        break;
      }
      if (r.type == 0x002f) throw const FormatException('XLS 已加密，请移除打开密码后重新导入');
      if (r.type == 0x0022 && _u16(d, 0) != 0) {
        throw const FormatException('暂不支持 1904 日期系统，请将日期列转为 YYYY-MM-DD 文本');
      }
      if (r.type == 0x0085) {
        if (d.length < 8) _invalid();
        if (d[5] != 0) {
          continue; // Charts and macro sheets contain no import rows.
        }
        final cursor = _StringCursor([Uint8List.sublistView(d, 6)]);
        final count = cursor.byte(), flags = cursor.byte();
        final name = cursor.characters(count, flags & 1 != 0);
        sheets.add((name: name, offset: _u32(d, 0)));
        if (sheets.length > 64) throw const FormatException('工作表过多，最多支持 64 张');
      }
      if (r.type == 0x00fc) {
        final chunks = [d];
        while (position + 4 <= data.length && _u16(data, position) == 0x003c) {
          final continuation = record(position);
          chunks.add(continuation.data);
          position = continuation.next;
        }
        final cursor = _StringCursor(chunks);
        final total = cursor.uint32(), count = cursor.uint32();
        if (count > total || count > 1000000 || strings.isNotEmpty) _invalid();
        for (var i = 0; i < count; i++) {
          strings.add(cursor.string());
        }
      }
    }
    if (!ended || sheets.map((s) => s.offset).toSet().length != sheets.length) {
      _invalid();
    }
    final result = <XlsRows>[];
    for (final sheet in sheets) {
      if (sheet.offset < position) _invalid();
      final rows = readSheet(sheet.offset);
      if (rows.length >= 2) result.add((name: sheet.name, rows: rows));
    }
    if (result.isEmpty) throw const FormatException('Excel 没有可导入的工作表');
    return result;
  }

  String number(double n) {
    if (!n.isFinite) throw const FormatException('Excel 包含无效数值');
    return n == n.truncateToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  double rk(int value) {
    final double n;
    if (value & 2 != 0) {
      n = (value >> 2).toSigned(30).toDouble();
    } else {
      final b = ByteData(8)..setUint32(4, value & 0xfffffffc, Endian.little);
      n = b.getFloat64(0, Endian.little);
    }
    return value & 1 != 0 ? n / 100 : n;
  }

  List<List<String>> readSheet(int offset) {
    final first = record(offset);
    bof(first, 0x10);
    var position = first.next;
    final rows = <int, Map<int, String>>{};
    void cell(int row, int col, String value) {
      if (col >= 100) throw const FormatException('最多支持 100 列');
      if (value.length > 10000) throw const FormatException('单元格最多 10000 字');
      if (value.isEmpty) return;
      final values = rows.putIfAbsent(row, () => {});
      if (rows.length > 10001) throw const FormatException('最多导入 10000 条明细');
      if (values.containsKey(col)) _invalid();
      values[col] = value;
    }

    while (position < data.length) {
      final r = record(position), d = r.data;
      position = r.next;
      if (r.type == 0x000a) {
        return [
          for (final row in rows.keys.toList()..sort())
            [
              for (
                var col = 0;
                col <= rows[row]!.keys.reduce((a, b) => a > b ? a : b);
                col++
              )
                rows[row]![col] ?? '',
            ],
        ];
      }
      if (r.type == 0x0006) {
        throw const FormatException('Excel 含公式，请先粘贴为值再导入');
      }
      if (r.type == 0x0203) {
        cell(
          _u16(d, 0),
          _u16(d, 2),
          number(ByteData.sublistView(d).getFloat64(6, Endian.little)),
        );
      } else if (r.type == 0x027e) {
        cell(_u16(d, 0), _u16(d, 2), number(rk(_u32(d, 6))));
      } else if (r.type == 0x00bd) {
        final count = (d.length - 6) ~/ 6, firstCol = _u16(d, 2);
        if (d.length < 12 ||
            (d.length - 6) % 6 != 0 ||
            _u16(d, d.length - 2) != firstCol + count - 1) {
          _invalid();
        }
        for (var i = 0; i < count; i++) {
          cell(_u16(d, 0), firstCol + i, number(rk(_u32(d, 6 + i * 6))));
        }
      } else if (r.type == 0x00fd) {
        final index = _u32(d, 6);
        if (index >= strings.length) _invalid();
        cell(_u16(d, 0), _u16(d, 2), strings[index]);
      } else if (r.type == 0x0204 || r.type == 0x00d6) {
        cell(
          _u16(d, 0),
          _u16(d, 2),
          _StringCursor([Uint8List.sublistView(d, 6)]).string(),
        );
      } else if (r.type == 0x0205) {
        if (d[7] != 0) throw const FormatException('Excel 包含错误单元格，请修正后重新导入');
        cell(_u16(d, 0), _u16(d, 2), d[6] == 0 ? 'false' : 'true');
      }
    }
    return _invalid();
  }
}

// CONTINUE records prepend an encoding flag only when splitting character data,
// not between strings or inside the rich-text / phonetic metadata.
class _StringCursor {
  _StringCursor(this.chunks);
  final List<Uint8List> chunks;
  int chunk = 0, position = 0;
  void next() {
    if (++chunk >= chunks.length || chunks[chunk].isEmpty) _invalid();
    position = 0;
  }

  int byte() {
    if (position == chunks[chunk].length) next();
    return chunks[chunk][position++];
  }

  int uint16() => byte() | byte() << 8;
  int uint32() => byte() | byte() << 8 | byte() << 16 | byte() << 24;
  String characters(int count, bool wide) {
    if (count > 10000) throw const FormatException('单元格最多 10000 字');
    final units = <int>[];
    for (var i = 0; i < count; i++) {
      if (position == chunks[chunk].length) {
        next();
        wide = byte() & 1 != 0;
      }
      if (wide && position + 2 > chunks[chunk].length) _invalid();
      units.add(wide ? uint16() : byte());
    }
    return String.fromCharCodes(units);
  }

  String string() {
    final length = uint16(), flags = byte();
    final runs = flags & 8 != 0 ? uint16() : 0;
    final extension = flags & 4 != 0 ? uint32() : 0;
    final value = characters(length, flags & 1 != 0);
    if (extension > 10 * 1024 * 1024) _invalid();
    for (var i = 0; i < runs * 4 + extension; i++) {
      byte();
    }
    return value;
  }
}
