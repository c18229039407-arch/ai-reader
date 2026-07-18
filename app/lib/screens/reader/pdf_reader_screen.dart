import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/models.dart';

/// PDF 原版式阅读（C8，MVP：查看 + 页码记忆；AI 选段解释对 PDF 为 V-next）。
class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.book,
    required this.filePath,
    required this.initialPage,
    required this.onPageChanged,
  });

  final Book book;
  final String filePath;
  final int initialPage;
  final void Function(int page, int total) onPageChanged;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_total > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_page / $_total'),
              ),
            ),
        ],
      ),
      body: PdfViewer.file(
        widget.filePath,
        controller: _controller,
        params: PdfViewerParams(
          onViewerReady: (document, controller) {
            setState(() => _total = document.pages.length);
            if (widget.initialPage > 1 &&
                widget.initialPage <= document.pages.length) {
              controller.goToPage(pageNumber: widget.initialPage);
            }
          },
          onPageChanged: (page) {
            if (page == null) return;
            setState(() => _page = page);
            widget.onPageChanged(page, _total);
          },
        ),
      ),
    );
  }
}
