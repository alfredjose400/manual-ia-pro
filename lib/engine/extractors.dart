import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import 'search_engine.dart';

/// Error al leer un documento. [code]: 'scanned' | 'oldDoc' | 'password' | 'damaged'
class ExtractError implements Exception {
  ExtractError(this.code);
  final String code;
  @override
  String toString() => 'ExtractError($code)';
}

/// ¿El texto extraído es ilegible? Pasa con PDF cuyas letras no traen su código (salen símbolos como «! " # $»).
bool looksGarbled(String t) {
  final chars = t.replaceAll(RegExp(r'\s'), '');
  if (chars.length < 30) return true; // casi sin texto: probablemente es una imagen
  final letters = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').allMatches(chars).length;
  if (letters / chars.length < 0.6) return true;
  // Palabras con vocales: en un texto real casi todas las tienen.
  final ws = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{2,}').allMatches(t).map((m) => m.group(0)!).toList();
  if (ws.isEmpty) return true;
  final withVowel = ws.where((w) => RegExp(r'[aeiouáéíóúàèìòùâêôãõAEIOUÁÉÍÓÚ]').hasMatch(w)).length;
  return withVowel / ws.length < 0.7;
}

/// Lee el texto de cada página de un PDF, en el propio teléfono.
/// Si una página no tiene texto legible, lo reconoce desde la imagen (OCR) sin internet.
/// [onProgress] recibe la fracción hecha (0..1) y si se está usando OCR.
Future<List<DocPage>> extractPdf(String path, {void Function(double done, bool ocr)? onProgress}) async {
  PdfDocument doc;
  try {
    doc = await PdfDocument.openFile(path);
  } on PdfPasswordException {
    throw ExtractError('password');
  } catch (_) {
    throw ExtractError('damaged');
  }
  final ocr = PageOcr();
  try {
    final pages = <DocPage>[];
    var chars = 0;
    var usedOcr = false;
    final count = doc.pages.length;
    for (var i = 0; i < count; i++) {
      final page = doc.pages[i];
      final text = await page.loadStructuredText();
      // Se conserva el largo del texto para que cada letra siga en su posición.
      final t = text.fullText.replaceAll('\r', '\n');
      DocPage result;
      if (looksGarbled(t)) {
        usedOcr = true;
        onProgress?.call(i / count, true);
        result = await ocr.readPage(page, i + 1);
      } else {
        result = DocPage.fromText(i + 1, t);
      }
      chars += result.text.trim().length;
      pages.add(result);
      onProgress?.call((i + 1) / count, usedOcr);
      // Deja respirar a la pantalla entre página y página.
      await Future<void>.delayed(Duration.zero);
    }
    if (chars < 20) throw ExtractError('scanned');
    return pages;
  } finally {
    await ocr.close();
    await doc.dispose();
  }
}

/// Reconocimiento de texto (OCR) con Google ML Kit. El modelo va dentro de la app: funciona sin internet.
class PageOcr {
  TextRecognizer? _recognizer;
  Directory? _tmp;

  Future<DocPage> readPage(PdfPage page, int number) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    _tmp ??= await getTemporaryDirectory();
    // Unos 1700 píxeles de ancho: suficiente para leer letra de 9-10 puntos.
    final scale = math.min(4.0, 1700 / page.width);
    final w = (page.width * scale).round(), h = (page.height * scale).round();
    final img = await page.render(
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (img == null) return DocPage(number: number, text: '', lines: const [], ocr: true);
    final File file;
    try {
      final image = await img.createImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      file = File('${_tmp!.path}/ocr_page.png');
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
    } finally {
      img.dispose();
    }
    final recognized = await _recognizer!.processImage(InputImage.fromFilePath(file.path));

    final buf = StringBuffer();
    final lines = <DocLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isEmpty) continue;
        if (buf.isNotEmpty) buf.write('\n');
        final start = buf.length;
        buf.write(t);
        final r = line.boundingBox;
        lines.add(DocLine(start, buf.length,
            box: [r.left / scale, r.top / scale, r.right / scale, r.bottom / scale]));
      }
    }
    return DocPage(number: number, text: buf.toString(), lines: lines, ocr: true);
  }

  Future<void> close() async {
    try {
      await _recognizer?.close();
    } catch (_) {}
    _recognizer = null;
  }
}

/// Lee un Word (.docx): párrafos, títulos (por su estilo) y saltos de página.
Future<List<DocPage>> extractDocx(String path) async {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
  } catch (_) {
    throw ExtractError('damaged');
  }
  final main = zip.findFile('word/document.xml');
  if (main == null) throw ExtractError('damaged');

  String read(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  // Estilos de título: «Heading 1», «Título 1», «Title»…
  final styleLevel = <String, int>{};
  final stylesFile = zip.findFile('word/styles.xml');
  if (stylesFile != null) {
    try {
      final styles = XmlDocument.parse(read(stylesFile));
      final headingName = RegExp(r'(heading|titulo|título)\s*(\d)', caseSensitive: false);
      for (final st in styles.findAllElements('w:style')) {
        final id = st.getAttribute('w:styleId');
        if (id == null) continue;
        final name = st.findElements('w:name').firstOrNull?.getAttribute('w:val')?.toLowerCase() ?? '';
        final m = headingName.firstMatch(name);
        final outline = st.findAllElements('w:outlineLvl').firstOrNull?.getAttribute('w:val');
        if (m != null) {
          styleLevel[id] = int.parse(m.group(2)!);
        } else if (outline != null && int.tryParse(outline) != null && int.parse(outline) < 9) {
          styleLevel[id] = int.parse(outline) + 1;
        } else if (name == 'title' || name == 'título' || name == 'titulo') {
          styleLevel[id] = 1;
        }
      }
    } catch (_) {}
  }

  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(read(main));
  } catch (_) {
    throw ExtractError('damaged');
  }

  final pages = <DocPage>[];
  var buf = StringBuffer();
  var lines = <DocLine>[];
  var sawBreaks = false;

  void flush() {
    if (lines.isEmpty) return;
    pages.add(DocPage(number: pages.length + 1, text: buf.toString(), lines: lines));
    buf = StringBuffer();
    lines = <DocLine>[];
  }

  void addLine(String t, int level) {
    if (buf.isNotEmpty) buf.write('\n');
    final start = buf.length;
    buf.write(t);
    lines.add(DocLine(start, buf.length, headingLevel: level));
  }

  for (final p in xml.findAllElements('w:p')) {
    // Párrafos dentro de cuadros de texto: su texto ya está en el párrafo que los contiene.
    if (p.ancestors.whereType<XmlElement>().any((a) => a.name.qualified == 'w:p')) continue;
    final text = StringBuffer();
    var breakBefore = false, breakAfter = false;
    for (final el in p.descendantElements) {
      switch (el.name.qualified) {
        case 'w:t':
          text.write(el.innerText);
        case 'w:tab':
        case 'w:cr':
          text.write(' ');
        case 'w:br':
          if (el.getAttribute('w:type') != 'page') {
            text.write(' ');
          } else {
            sawBreaks = true;
            if (text.isEmpty) {
              breakBefore = true;
            } else {
              breakAfter = true;
            }
          }
        case 'w:lastRenderedPageBreak':
          sawBreaks = true;
          if (text.isEmpty) {
            breakBefore = true;
          } else {
            breakAfter = true;
          }
      }
    }
    final pPr = p.findElements('w:pPr').firstOrNull;
    if (pPr?.findElements('w:pageBreakBefore').isNotEmpty ?? false) {
      breakBefore = true;
      sawBreaks = true;
    }
    final styleId = pPr?.findElements('w:pStyle').firstOrNull?.getAttribute('w:val');
    final outline = pPr?.findElements('w:outlineLvl').firstOrNull?.getAttribute('w:val');
    var level = styleLevel[styleId] ?? 0;
    if (level == 0 && outline != null && (int.tryParse(outline) ?? 9) < 9) level = int.parse(outline) + 1;

    if (breakBefore) flush();
    final t = text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    // Sin estilo de título: la app decide por el texto (null).
    if (t.isNotEmpty) addLine(t, level);
    if (breakAfter) flush();
  }
  flush();

  // Si el archivo no guarda saltos de página, se arman páginas aproximadas de ~3000 letras.
  if (!sawBreaks && pages.length == 1 && pages.first.text.length > 3500) {
    final all = pages.first;
    pages.clear();
    for (var i = 0; i < all.lines.length; i++) {
      if (buf.length > 3000) flush();
      final l = all.lines[i];
      addLine(all.line(i), l.headingLevel ?? 0);
    }
    flush();
  }

  // Los párrafos sin estilo de título se evalúan por su texto (numeración, MAYÚSCULAS).
  final result = [
    for (final pg in pages)
      DocPage(number: pg.number, text: pg.text, lines: [
        for (final l in pg.lines) DocLine(l.start, l.end, headingLevel: (l.headingLevel ?? 0) > 0 ? l.headingLevel : null),
      ]),
  ];
  if (result.fold<int>(0, (a, p) => a + p.text.trim().length) < 20) throw ExtractError('damaged');
  return result;
}
