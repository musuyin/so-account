import fs from 'node:fs/promises';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtime = path.resolve(process.argv[4] ?? path.join(root, '.tooling/template-builder'));
const artifactEntry = createRequire(import.meta.url).resolve('@oai/artifact-tool', { paths: [runtime] });
const { Workbook, SpreadsheetFile } = await import(pathToFileURL(artifactEntry).href);
const outputDir = path.resolve(process.argv[2] ?? path.join(root, 'outputs/import-template'));
const dart = process.argv[3] ?? path.join(root, '.tooling/flutter/bin/cache/dart-sdk/bin/dart.exe');
const rows = JSON.parse(execFileSync(dart, [path.join(root, 'tool/export_import_template.dart')],
  { encoding: 'utf8', windowsHide: true, cwd: root }));
const book = Workbook.create();
const sheet = book.worksheets.add('账单');
sheet.getRangeByIndexes(0, 0, rows.length, rows[0].length).values = rows.map((row, i) =>
  i === 0 ? row : row.map((value, column) => column === 0
    ? new Date(value.replace(' ', 'T') + ':00Z')
    : column === 2 ? Number(value) : value));
const grid = sheet.getRange('A1:W3');
grid.format.font = { name: 'Arial', size: 11, color: '#202020' };
grid.format.rowHeight = 25;
grid.format.columnWidth = 14;
grid.format.verticalAlignment = 'center';
sheet.getRange('A1:W1').format = {
  fill: '#426638', font: { name: 'Arial', size: 11, bold: true, color: '#FFFFFF' },
  horizontalAlignment: 'center', rowHeight: 28,
};
sheet.getRange('A1:A3').format.columnWidth = 22;
sheet.getRange('E1:E3').format.columnWidth = 20;
sheet.getRange('J1:J3').format.columnWidth = 38;
sheet.getRange('A2:A3').setNumberFormat('yyyy-mm-dd hh:mm');
sheet.getRange('C2:C3').setNumberFormat('0.00');
sheet.getRange('A2:B3').format.horizontalAlignment = 'left';
sheet.getRange('C2:C3').format.horizontalAlignment = 'right';
sheet.freezePanes.freezeRows(1);
sheet.showGridLines = true;
book.recalculate();
await fs.mkdir(outputDir, { recursive: true });
const output = path.join(outputDir, 'SoAccount-单级收支导入模板.xlsx');
await (await SpreadsheetFile.exportXlsx(book)).save(output);
for (const [name, range] of [['core', 'A1:J3'], ['extra', 'K1:W3']]) {
  const preview = await book.render({ sheetName: '账单', range, scale: 1.5, format: 'png' });
  await fs.writeFile(path.join(outputDir, `template-${name}.png`), new Uint8Array(await preview.arrayBuffer()));
}
await fs.mkdir(path.join(root, 'assets/templates'), { recursive: true });
await fs.copyFile(output, path.join(root, 'assets/templates/income_expense_template.xlsx'));
console.log(JSON.stringify({ output, columns: rows[0].length, sampleRows: rows.length - 1 }));
