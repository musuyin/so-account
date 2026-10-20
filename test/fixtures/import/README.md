# Synthetic import fixtures

All values are invented test data. `tool/generate_xls_fixtures.py` uses independent xlwt 1.3.0 / olefile 0.47 (development only; not app dependencies) to create BIFF8 XLS workbooks. Run with those packages on Python's module path to regenerate.

- `ledger.xls`: Chinese sheets/headers, UTF-16 surrogate pairs, numeric Excel date, negative/decimal RK values, sparse rows, multiple and empty sheets.
- `mini-stream.xls`: same Workbook stored in the CFB mini stream instead of regular FAT sectors; the generator changes only the container.
- `shared-strings.xls`: 1201 rows, Chinese/ASCII/emoji shared strings, SST/CONTINUE boundaries and an 8500-character cell split across records.
- `formula.xls`: a real formula record, which the application must reject without evaluating.
- `date1904.xls`: the 1904 date system, which must be explicitly rejected to avoid shifting dates.
