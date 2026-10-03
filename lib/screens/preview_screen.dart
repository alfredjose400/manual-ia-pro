import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../engine/search_engine.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/doc_actions.dart';

/// Vista previa del documento adjunto (sin internet).
/// Pestaña «Documento»: el PDF tal cual, con zoom. Pestaña «Texto leído»: el texto que usa la búsqueda.
class DocumentPreviewScreen extends StatelessWidget {
  const DocumentPreviewScreen({super.key, required this.doc, this.initialPage = 1});
  final DocumentInfo doc;
  final int initialPage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = state.l;
    final isPdf = doc.type == 'pdf';
    return DefaultTabController(
      length: 2,
      initialIndex: isPdf ? 0 : 1,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          titleSpacing: 0,
          title: Text(doc.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: l.download,
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => showDownloadSheet(context, doc),
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 14, fontWeight: FontWeight.w800),
            tabs: [Tab(text: l.previewTab), Tab(text: l.textTab)],
          ),
        ),
        body: Column(children: [
          if (doc.ocr)
            Container(
              width: double.infinity,
              color: AppColors.amberBg,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.document_scanner_outlined, size: 18, color: AppColors.amberText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.ocrNote, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.amberText)),
                ),
              ]),
            ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(), // el deslizamiento es para mover y ampliar el documento
              children: [
                isPdf
                    ? PdfViewer.file(state.sourcePathOf(doc)!, initialPageNumber: initialPage)
                    : _TextPages(doc: doc, initialPage: initialPage),
                _TextPages(doc: doc, initialPage: initialPage),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Texto leído de cada página (el que usa la búsqueda). Se puede ampliar con dos dedos y seleccionar.
class _TextPages extends StatelessWidget {
  const _TextPages({required this.doc, required this.initialPage});
  final DocumentInfo doc;
  final int initialPage;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final l = state.l;
    return FutureBuilder<DocIndex>(
      future: state.library.index(doc),
      builder: (context, snap) {
        final ix = snap.data;
        if (ix == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            itemCount: ix.pages.length,
            itemBuilder: (context, i) {
              final p = ix.pages[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l.pageWord} ${p.number}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  SelectableText(
                    p.text.trim().isEmpty ? l.emptyPage : p.text.trim(),
                    style: const TextStyle(fontFamily: 'serif', fontSize: 13.5, height: 1.5, color: AppColors.ink),
                  ),
                ]),
              );
            },
          ),
        );
      },
    );
  }
}
