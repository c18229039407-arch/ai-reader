import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 书摘分享卡片主题（三款：暖纸 / 夜墨 / 松绿）。
class CardTheme {
  const CardTheme(this.name, this.bg, this.fg, this.accent, this.quoteMark);

  final String name;
  final Color bg;
  final Color fg;
  final Color accent;
  final Color quoteMark;
}

const shareCardThemes = [
  CardTheme('暖纸', Color(0xFFF7F3EA), Color(0xFF2C2A26), Color(0xFF2E6B4F),
      Color(0x1A2E6B4F)),
  CardTheme('夜墨', Color(0xFF1C1F26), Color(0xFFE8E6E0), Color(0xFF7FB59A),
      Color(0x1AFFFFFF)),
  CardTheme('松绿', Color(0xFF2E6B4F), Color(0xFFF3F1EA), Color(0xFFCDE3D6),
      Color(0x22FFFFFF)),
];

/// 书摘卡片视图（用于 RepaintBoundary 截图导出）。
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.quote,
    required this.bookTitle,
    required this.author,
    required this.theme,
  });

  final String quote;
  final String bookTitle;
  final String author;
  final CardTheme theme;

  @override
  Widget build(BuildContext context) {
    const serif = ['Songti SC', 'STSong', 'Noto Serif SC', 'serif'];
    // 固定物理尺寸，导出比例稳定（1080×1350 由 pixelRatio 放大得到）
    return Container(
      width: 360,
      constraints: const BoxConstraints(minHeight: 360),
      color: theme.bg,
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“',
              style: TextStyle(
                  fontSize: 72,
                  height: 0.9,
                  fontFamilyFallback: serif,
                  color: theme.accent.withValues(alpha: .55))),
          const SizedBox(height: 4),
          Text(
            quote,
            style: TextStyle(
              fontSize: quote.length > 80 ? 19 : 22,
              height: 1.8,
              color: theme.fg,
              fontFamilyFallback: serif,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 28),
          Container(width: 40, height: 2, color: theme.accent),
          const SizedBox(height: 14),
          Text('《$bookTitle》',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.fg,
                  fontFamilyFallback: serif)),
          if (author.isNotEmpty && author != '未知作者') ...[
            const SizedBox(height: 4),
            Text(author,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.fg.withValues(alpha: .6),
                    fontFamilyFallback: serif)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.local_florist, size: 14, color: theme.accent),
              const SizedBox(width: 6),
              Text('林间阅读',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      color: theme.fg.withValues(alpha: .5))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 把 RepaintBoundary 截图导出为 PNG 文件，返回路径。
Future<String> exportCardPng(GlobalKey boundaryKey, String bookTitle) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final data = bytes!.buffer.asUint8List();
  return _writePng(data, bookTitle);
}

Future<String> _writePng(Uint8List data, String bookTitle) async {
  Directory dir;
  try {
    dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final safe = bookTitle.replaceAll(RegExp(r'[^\w一-鿿]+'), '_');
  final ts = DateTime.now().millisecondsSinceEpoch;
  final file = File(p.join(dir.path, '林间书摘_${safe}_$ts.png'));
  await file.writeAsBytes(data);
  return file.path;
}
