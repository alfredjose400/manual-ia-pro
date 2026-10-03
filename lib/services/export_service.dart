import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../engine/search_engine.dart';
import '../engine/text_utils.dart';

/// Párrafo del documento para exportar.
class ExportBlock {
  const ExportBlock({required this.page, required this.section, required this.text, required this.heading});
  final int page;
  final String section;
  final String text;
  final bool heading;
}

/// Textos de las columnas y etiquetas (en el idioma de la app).
class ExportLabels {
  const ExportLabels({required this.page, required this.section, required this.text, required this.sheet});
  final String page;
  final String section;
  final String text;
  final String sheet;
}

/// Convierte el texto leído del documento a Word (.docx) o Excel (.xlsx).
/// Todo se arma en el teléfono, sin internet.
class ExportService {
  /// Une las líneas de cada página en párrafos y separa los títulos.
  static List<ExportBlock> blocks(List<DocPage> pages) {
    final out = <ExportBlock>[];
    var section = '';
    for (final p in pages) {
      var para = <String>[];
      void flush() {
        if (para.isEmpty) return;
        out.add(ExportBlock(page: p.number, section: section, text: _joinParagraph(para), heading: false));
        para = <String>[];
      }

      for (var i = 0; i < p.lines.length; i++) {
        final t = p.line(i).replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isEmpty) continue;
        final styled = p.lines[i].headingLevel;
        final isHead = styled != null ? styled > 0 : looksLikeHeading(t);
        if (isHead) {
          flush();
          section = t;
          out.add(ExportBlock(page: p.number, section: section, text: t, heading: true));
          continue;
        }
        if ((isListItem(t) || _letterItem.hasMatch(t)) && para.isNotEmpty) flush();
        para.add(t);
        if (t.endsWith('.') || t.endsWith(':') || t.endsWith(';')) flush();
      }
      flush();
    }
    return out;
  }

  /// Incisos: "a) …", "b. …".
  static final _letterItem = RegExp(r'^[a-zA-Z][.)]\s');

  /// Une líneas cortadas: "transfe-" + "rencia" → "transferencia".
  static String _joinParagraph(List<String> lines) {
    final b = StringBuffer();
    for (final t in lines) {
      if (b.isEmpty) {
        b.write(t);
        continue;
      }
      final cur = b.toString();
      if (RegExp(r'[A-Za-zÀ-ÿ]-$').hasMatch(cur)) {
        b
          ..clear()
          ..write(cur.substring(0, cur.length - 1))
          ..write(t);
      } else {
        b.write(' $t');
      }
    }
    return b.toString();
  }

  // ---------------- Word (.docx) ----------------
  static Uint8List toDocx(String title, List<DocPage> pages, ExportLabels labels) {
    final body = StringBuffer();
    body.write(_wPara(title, bold: true, size: 32, after: 240));
    var lastPage = 0;
    for (final b in blocks(pages)) {
      if (b.page != lastPage) {
        if (lastPage != 0) body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
        body.write(_wPara('${labels.page} ${b.page}', size: 18, color: '6B7280', after: 120));
        lastPage = b.page;
      }
      body.write(b.heading
          ? _wPara(b.text, bold: true, size: 24, before: 200, after: 120)
          : _wPara(b.text, size: 22, after: 120, justify: true));
    }
    final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
        '$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
    return _zip({
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
          'Target="word/document.xml"/></Relationships>',
      'word/document.xml': doc,
    });
  }

  static String _wPara(String text,
      {bool bold = false, int size = 22, String? color, int before = 0, int after = 0, bool justify = false}) {
    final rPr = StringBuffer();
    if (bold) rPr.write('<w:b/>');
    if (color != null) rPr.write('<w:color w:val="$color"/>');
    rPr.write('<w:sz w:val="$size"/>');
    return '<w:p><w:pPr><w:spacing w:before="$before" w:after="$after"/>${justify ? '<w:jc w:val="both"/>' : ''}</w:pPr>'
        '<w:r><w:rPr>$rPr</w:rPr><w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  // ---------------- Excel (.xlsx) ----------------
  static Uint8List toXlsx(List<DocPage> pages, ExportLabels labels) {
    final rows = StringBuffer();
    String str(String ref, String v, int style) =>
        '<c r="$ref" t="inlineStr" s="$style"><is><t xml:space="preserve">${_esc(_cell(v))}</t></is></c>';
    rows.write('<row r="1">${str('A1', labels.page, 1)}${str('B1', labels.section, 1)}${str('C1', labels.text, 1)}</row>');
    var r = 1;
    for (final b in blocks(pages)) {
      if (b.heading) continue; // el título queda en la columna Sección
      r++;
      rows.write('<row r="$r"><c r="A$r" s="2"><v>${b.page}</v></c>${str('B$r', b.section, 2)}${str('C$r', b.text, 2)}</row>');
    }
    final sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>'
        '<cols><col min="1" max="1" width="9" customWidth="1"/><col min="2" max="2" width="38" customWidth="1"/>'
        '<col min="3" max="3" width="110" customWidth="1"/></cols>'
        '<sheetData>$rows</sheetData><autoFilter ref="A1:C$r"/></worksheet>';
    final sheetName = _esc(labels.sheet.length > 31 ? labels.sheet.substring(0, 31) : labels.sheet);
    return _zip({
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
          'Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
          '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
          '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1">'
          '<alignment vertical="top" wrapText="1"/></xf></cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
          '</styleSheet>',
      'xl/worksheets/sheet1.xml': sheet,
    });
  }

  /// Excel admite hasta 32767 letras por celda.
  static String _cell(String v) => v.length > 32000 ? v.substring(0, 32000) : v;

  static final _invalidXml = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]');

  static String _esc(String s) => s
      .replaceAll(_invalidXml, '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Uint8List _zip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    final List<int>? out = ZipEncoder().encode(archive);
    return Uint8List.fromList(out ?? const <int>[]);
  }
}

/// Datos para armar el archivo en otro hilo (así la app no se congela).
typedef ExportJob = ({String format, String title, List<DocPage> pages, ExportLabels labels});

/// Arma el Word o Excel. Se usa con `compute(buildExport, job)`.
Uint8List buildExport(ExportJob job) => job.format == 'docx'
    ? ExportService.toDocx(job.title, job.pages, job.labels)
    : ExportService.toXlsx(job.pages, job.labels);
