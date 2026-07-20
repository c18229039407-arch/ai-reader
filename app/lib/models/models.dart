/// 核心数据模型（与 docs/architecture.md §3 对应，MVP 采用 JSON 持久化）。
library;

/// 书架中的一本书。
class Book {
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.format,
    required this.addedAt,
    this.lang = '',
    List<String>? tags,
  }) : tags = tags ?? [];

  final String id; // 文件内容 sha1 前 16 位
  final String title;
  final String author;
  final String filePath; // 库目录内的相对路径
  final String format; // epub | txt | pdf
  final String lang;
  final DateTime addedAt;

  /// 自定义标签（B3）。
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'format': format,
        'lang': lang,
        'addedAt': addedAt.toIso8601String(),
        'tags': tags,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String? ?? '未知书名',
        author: j['author'] as String? ?? '未知作者',
        filePath: j['filePath'] as String,
        format: j['format'] as String? ?? 'epub',
        lang: j['lang'] as String? ?? '',
        addedAt:
            DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
        tags: ((j['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
      );

  Book copyWith({String? title, String? author, List<String>? tags}) => Book(
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        filePath: filePath,
        format: format,
        lang: lang,
        addedAt: addedAt,
        tags: tags ?? this.tags,
      );
}

/// 段落级定位符："chapterIndex:paragraphIndex"。
class Locator {
  const Locator(this.chapter, this.paragraph);

  final int chapter;
  final int paragraph;

  @override
  String toString() => '$chapter:$paragraph';

  static Locator? parse(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final c = int.tryParse(parts[0]), p = int.tryParse(parts[1]);
    if (c == null || p == null) return null;
    return Locator(c, p);
  }

  @override
  bool operator ==(Object other) =>
      other is Locator &&
      other.chapter == chapter &&
      other.paragraph == paragraph;

  @override
  int get hashCode => Object.hash(chapter, paragraph);
}

/// 阅读进度（C4）。
class ReadingState {
  ReadingState({
    required this.chapterIndex,
    required this.scrollOffset,
    required this.percent,
    required this.updatedAt,
  });

  final int chapterIndex;
  final double scrollOffset;
  final double percent; // 0..1，粗粒度整书进度
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'chapterIndex': chapterIndex,
        'scrollOffset': scrollOffset,
        'percent': percent,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ReadingState.fromJson(Map<String, dynamic> j) => ReadingState(
        chapterIndex: (j['chapterIndex'] as num?)?.toInt() ?? 0,
        scrollOffset: (j['scrollOffset'] as num?)?.toDouble() ?? 0,
        percent: (j['percent'] as num?)?.toDouble() ?? 0,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  static ReadingState initial() => ReadingState(
      chapterIndex: 0, scrollOffset: 0, percent: 0, updatedAt: DateTime.now());
}

/// 高亮（C5，MVP 为段落级）。
class Highlight {
  Highlight(
      {required this.locator,
      required this.colorIndex,
      required this.createdAt,
      this.start,
      this.end,
      this.snippet});

  final Locator locator;
  final int colorIndex; // 对应预置高亮色板
  final DateTime createdAt;

  /// 段内字符范围（句级高亮）；为 null 表示整段高亮（旧数据兼容）。
  final int? start;
  final int? end;

  /// 高亮的文字内容（用于标注列表展示与跨设备容错）。
  final String? snippet;

  bool get isRange => start != null && end != null;

  /// 是否与另一段内范围重叠（用于再次划选同一处时取消高亮）。
  bool overlaps(int s, int e) =>
      isRange ? (s < end! && e > start!) : true;

  Map<String, dynamic> toJson() => {
        'locator': locator.toString(),
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (snippet != null) 'snippet': snippet,
      };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        locator:
            Locator.parse(j['locator'] as String? ?? '') ?? const Locator(0, 0),
        colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        start: (j['start'] as num?)?.toInt(),
        end: (j['end'] as num?)?.toInt(),
        snippet: j['snippet'] as String?,
      );
}

/// 段落笔记（C6）。
class NoteAnn {
  NoteAnn({required this.locator, required this.text, required this.createdAt});

  final Locator locator;
  String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'locator': locator.toString(),
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NoteAnn.fromJson(Map<String, dynamic> j) => NoteAnn(
        locator:
            Locator.parse(j['locator'] as String? ?? '') ?? const Locator(0, 0),
        text: j['text'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 书签（C6）：记章节 + 滚动位置。
class Bookmark {
  Bookmark({
    required this.chapterIndex,
    required this.scrollOffset,
    required this.label,
    required this.createdAt,
  });

  final int chapterIndex;
  final double scrollOffset;
  final String label;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'chapterIndex': chapterIndex,
        'scrollOffset': scrollOffset,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        chapterIndex: (j['chapterIndex'] as num?)?.toInt() ?? 0,
        scrollOffset: (j['scrollOffset'] as num?)?.toDouble() ?? 0,
        label: j['label'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 留存的 AI 解释（D8 锚点）。
class Explanation {
  Explanation({
    required this.id,
    required this.locator,
    required this.term,
    required this.contextExcerpt,
    required this.resultText,
    required this.mode, // explain | translate
    required this.createdAt,
  });

  final String id;
  final Locator locator;
  final String term; // 被选中的文本（截断保存）
  final String contextExcerpt;
  final String resultText;
  final String mode;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'locator': locator.toString(),
        'term': term,
        'contextExcerpt': contextExcerpt,
        'resultText': resultText,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Explanation.fromJson(Map<String, dynamic> j) => Explanation(
        id: j['id'] as String,
        locator:
            Locator.parse(j['locator'] as String? ?? '') ?? const Locator(0, 0),
        term: j['term'] as String? ?? '',
        contextExcerpt: j['contextExcerpt'] as String? ?? '',
        resultText: j['resultText'] as String? ?? '',
        mode: j['mode'] as String? ?? 'explain',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 一本书的全部本地状态（进度 + 高亮 + 解释），对应 state/<bookId>.json。
class BookState {
  BookState({
    required this.reading,
    required this.highlights,
    required this.explanations,
    List<NoteAnn>? notes,
    List<Bookmark>? bookmarks,
  })  : notes = notes ?? [],
        bookmarks = bookmarks ?? [];

  ReadingState reading;
  final List<Highlight> highlights;
  final List<Explanation> explanations;
  final List<NoteAnn> notes; // C6
  final List<Bookmark> bookmarks; // C6

  Map<String, dynamic> toJson() => {
        'reading': reading.toJson(),
        'highlights': highlights.map((h) => h.toJson()).toList(),
        'explanations': explanations.map((e) => e.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
      };

  factory BookState.fromJson(Map<String, dynamic> j) => BookState(
        reading: j['reading'] != null
            ? ReadingState.fromJson(j['reading'] as Map<String, dynamic>)
            : ReadingState.initial(),
        highlights: ((j['highlights'] as List?) ?? [])
            .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
            .toList(),
        explanations: ((j['explanations'] as List?) ?? [])
            .map((e) => Explanation.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: ((j['notes'] as List?) ?? [])
            .map((e) => NoteAnn.fromJson(e as Map<String, dynamic>))
            .toList(),
        bookmarks: ((j['bookmarks'] as List?) ?? [])
            .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static BookState empty() => BookState(
      reading: ReadingState.initial(), highlights: [], explanations: []);
}

/// 用户画像（D7）。
class UserProfile {
  UserProfile({
    this.occupation = '',
    this.interests = '',
    this.freeDescription = '',
    this.personalizeOn = true,
  });

  String occupation;
  String interests;
  String freeDescription;
  bool personalizeOn;

  bool get isEmpty =>
      occupation.trim().isEmpty &&
      interests.trim().isEmpty &&
      freeDescription.trim().isEmpty;

  /// 注入提示词的画像描述；关闭个性化或画像为空时返回空串。
  String promptFragment() {
    if (!personalizeOn || isEmpty) return '';
    final parts = <String>[
      if (occupation.trim().isNotEmpty) '职业：${occupation.trim()}',
      if (interests.trim().isNotEmpty) '兴趣：${interests.trim()}',
      if (freeDescription.trim().isNotEmpty) '补充：${freeDescription.trim()}',
    ];
    return '读者背景（${parts.join('；')}）。举例时请优先使用贴合该背景的日常场景做类比。';
  }
}
