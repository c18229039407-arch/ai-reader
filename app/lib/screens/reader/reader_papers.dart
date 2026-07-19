import 'package:flutter/material.dart';

/// 阅读纸张（C3 扩展）：背景/文字成套配色。
class ReaderPaper {
  const ReaderPaper({
    required this.name,
    required this.bg,
    required this.fg,
    this.isDark = false,
  });

  final String name;
  final Color? bg; // null = 跟随系统主题
  final Color? fg;
  final bool isDark;
}

const readerPapers = <ReaderPaper>[
  ReaderPaper(name: '跟随系统', bg: null, fg: null),
  ReaderPaper(name: '纯白', bg: Color(0xFFFFFFFF), fg: Color(0xFF1F2328)),
  ReaderPaper(name: '暖白', bg: Color(0xFFF7F4EC), fg: Color(0xFF2B2A26)),
  ReaderPaper(name: '羊皮纸', bg: Color(0xFFF5ECD9), fg: Color(0xFF3D3426)),
  ReaderPaper(name: '豆沙绿', bg: Color(0xFFE3EDD9), fg: Color(0xFF27362A)),
  ReaderPaper(name: '青灰', bg: Color(0xFFE8EDF0), fg: Color(0xFF26313A)),
  ReaderPaper(name: '牛皮纸', bg: Color(0xFFE9DAC0), fg: Color(0xFF423320)),
  ReaderPaper(
      name: '夜间黑', bg: Color(0xFF17191C), fg: Color(0xFFB8BCC2), isDark: true),
  ReaderPaper(
      name: '夜蓝', bg: Color(0xFF16202B), fg: Color(0xFFAEBFCE), isDark: true),
];
