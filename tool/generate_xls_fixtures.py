"""Generate synthetic BIFF8 fixtures using independent xlwt 1.3.0 (dev only)."""
import datetime
import math
from pathlib import Path
import struct

import xlwt
import olefile


ROOT = Path(__file__).resolve().parent.parent / 'test/fixtures/import'


def mini_compound(source, target):
    with olefile.OleFileIO(source) as ole:
        stream = ole.openstream('Workbook').read()
    position = 0
    while position + 4 < len(stream):
        kind, size = struct.unpack_from('<HH', stream, position)
        if kind == size == 0:
            break
        position += size + 4
    stream = stream[:position]
    assert len(stream) < 4096
    mini_count = math.ceil(len(stream) / 64)
    root_size = mini_count * 64
    block_count = math.ceil(root_size / 512)
    fat_id = 2 + block_count
    FREE, END, FAT = 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFD
    header = bytearray(512)
    header[:8] = bytes.fromhex('d0cf11e0a1b11ae1')
    struct.pack_into('<HHHHH', header, 24, 0x3E, 3, 0xFFFE, 9, 6)
    struct.pack_into('<IIIIIIIII', header, 40, 0, 1, 0, 0, 4096, 1, 1, END, 0)
    struct.pack_into('<109I', header, 76, fat_id, *([FREE] * 108))
    directory = bytearray(512)
    for index, name, kind, start, size in [
        (0, 'Root Entry', 5, 2, root_size), (1, 'Workbook', 2, 0, len(stream)),
    ]:
        offset = index * 128
        encoded = (name + '\0').encode('utf-16-le')
        directory[offset:offset + len(encoded)] = encoded
        struct.pack_into('<HBBIII', directory, offset + 64, len(encoded), kind, 1,
                         FREE, FREE, 1 if index == 0 else FREE)
        struct.pack_into('<IQ', directory, offset + 116, start, size)
    mini_fat = [i + 1 if i < mini_count - 1 else END for i in range(mini_count)]
    mini_fat.extend([FREE] * (128 - len(mini_fat)))
    fat = [END, END] + [i + 1 if i < fat_id - 1 else END for i in range(2, fat_id)] + [FAT]
    fat.extend([FREE] * (128 - len(fat)))
    target.write_bytes(header + directory + struct.pack('<128I', *mini_fat)
                       + stream.ljust(block_count * 512, b'\0') + struct.pack('<128I', *fat))


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    book = xlwt.Workbook()
    sheet = book.add_sheet('日常明细')
    headers = ['日期', '金额', '账户', '分类', '类型', '备注']
    for column, header in enumerate(headers):
        sheet.write(0, column, header)
    date = xlwt.easyxf(num_format_str='YYYY-MM-DD')
    sheet.write(1, 0, datetime.datetime(2026, 10, 20), date)
    for column, value in enumerate([12.5, '现金', '普通餐饮', '支出', '午餐 🥒'], 1):
        sheet.write(1, column, value)
    for column, value in enumerate(['2026-10-19', -9.99, '', '工资', '收入', '补记']):
        sheet.write(4, column, value)
    second = book.add_sheet('备用明细')
    for row, values in enumerate([['日期', '金额'], ['2026-10-18', 0.1]]):
        for column, value in enumerate(values):
            second.write(row, column, value)
    book.add_sheet('空表')
    book.save(str(ROOT / 'ledger.xls'))
    mini_compound(ROOT / 'ledger.xls', ROOT / 'mini-stream.xls')

    book = xlwt.Workbook()
    sheet = book.add_sheet('长共享字符串')
    for column, value in enumerate(['日期', '金额', '备注']):
        sheet.write(0, column, value)
    for row in range(1, 1201):
        sheet.write(row, 0, '2026-10-20')
        sheet.write(row, 1, row / 100)
        sheet.write(row, 2, f'第{row}条中文备注-ASCII-🥒')
    sheet.write(1201, 0, '2026-10-20')
    sheet.write(1201, 1, 8.25)
    sheet.write(1201, 2, '长' * 8500)
    book.save(str(ROOT / 'shared-strings.xls'))

    for name in ['formula', 'date1904']:
        book = xlwt.Workbook()
        book.dates_1904 = name == 'date1904'
        sheet = book.add_sheet('明细')
        sheet.write(0, 0, '日期')
        sheet.write(0, 1, '金额')
        sheet.write(1, 0, '2026-10-20')
        sheet.write(1, 1, xlwt.Formula('1+2') if name == 'formula' else 12.5)
        book.save(str(ROOT / f'{name}.xls'))
    print('Generated XLS fixtures:', ', '.join(p.name for p in sorted(ROOT.glob('*.xls'))))


if __name__ == '__main__':
    main()
