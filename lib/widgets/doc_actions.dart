import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/preview_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Abre la vista previa del documento.
void openPreview(BuildContext context, DocumentInfo doc) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocumentPreviewScreen(doc: doc)));
}

/// Hoja para elegir el formato de descarga: Word o Excel.
Future<void> showDownloadSheet(BuildContext context, DocumentInfo doc) async {
  final l = context.read<AppState>().l;
  final format = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 14),
          Text(l.downloadAs, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 12),
          _FormatTile(
            color: const Color(0xFF2F6BEA),
            label: 'W',
            title: l.asWord,
            subtitle: l.asWordSub,
            onTap: () => Navigator.pop(ctx, 'docx'),
          ),
          const SizedBox(height: 10),
          _FormatTile(
            color: const Color(0xFF13804A),
            label: 'X',
            title: l.asExcel,
            subtitle: l.asExcelSub,
            onTap: () => Navigator.pop(ctx, 'xlsx'),
          ),
        ]),
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  await downloadAs(context, doc, format);
}

/// Crea el archivo y pide dónde guardarlo.
Future<void> downloadAs(BuildContext context, DocumentInfo doc, String format) async {
  final state = context.read<AppState>();
  final l = state.l;
  showSnack(context, l.preparing);
  try {
    final saved = await state.exportDocument(doc, format);
    if (saved && context.mounted) showSnack(context, l.savedOk);
  } catch (_) {
    if (context.mounted) showSnack(context, l.saveError);
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.color, required this.label, required this.title, required this.subtitle, required this.onTap});
  final Color color;
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ]),
            ),
            const Icon(Icons.file_download_outlined, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}
