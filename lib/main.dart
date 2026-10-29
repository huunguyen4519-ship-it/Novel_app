import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovelApp());
}

// ================= HẰNG SỐ =================

const List<Color> kThemeColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFA855F7),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

const Color kWhite90 = Color(0xE6FFFFFF);
const Color kBg = Color(0xFF08080A);

extension ColorFade on Color {
  Color fade(double opacity) => withAlpha((opacity * 255).round());
}

// ================= TIỆN ÍCH =================

bool _isWhitespace(int unit) {
  return unit == 0x20 ||
      (unit >= 0x09 && unit <= 0x0D) ||
      unit == 0x85 ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000;
}

/// Đếm từ Unicode-safe: bỏ qua dấu thanh tiếng Việt khi đếm bằng cách
/// duyệt code unit. Không tạo list trung gian nên rất nhanh.
int countWords(String text) {
  var count = 0;
  var inWord = false;
  for (final unit in text.codeUnits) {
    if (_isWhitespace(unit)) {
      inWord = false;
    } else if (!inWord) {
      inWord = true;
      count++;
    }
  }
  return count;
}

String previewText(String text, {int maxChars = 240}) {
  if (text.length <= maxChars) return text;
  var end = maxChars;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return text.substring(0, end);
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String stripMarkdown(String text) {
  return text
      .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
      .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
      .replaceAll(RegExp(r'__(.+?)__'), r'$1')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n+'), ' ')
      .trim();
}

// ================= MARKDOWN =================

/// Parse markdown inline thành TextSpan để hiển thị.
TextSpan parseInlineMarkdown(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  final regex = RegExp(r'(\*\*(.+?)\*\*)|(\*(.+?)\*)|(__(.+?)__)');
  var lastEnd = 0;
  for (final match in regex.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    if (match.group(2) != null) {
      spans.add(TextSpan(
        text: match.group(2),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
    } else if (match.group(4) != null) {
      spans.add(TextSpan(
        text: match.group(4),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    } else if (match.group(6) != null) {
      spans.add(TextSpan(
        text: match.group(6),
        style: const TextStyle(decoration: TextDecoration.underline),
      ));
    }
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }
  return TextSpan(style: baseStyle, children: spans);
}

/// Render toàn bộ markdown thành widget (dùng cho preview).
Widget renderMarkdown(String markdown, Color themeColor) {
  final lines = markdown.split('\n');
  final children = <Widget>[];
  const base = TextStyle(color: kWhite90, fontSize: 16, height: 1.6);

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      children.add(const SizedBox(height: 12));
      continue;
    }
    if (trimmed.startsWith('# ')) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: RichText(
          text: parseInlineMarkdown(
            trimmed.substring(2),
            base.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
        ),
      ));
    } else if (trimmed.startsWith('## ')) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: RichText(
          text: parseInlineMarkdown(
            trimmed.substring(3),
            base.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
        ),
      ));
    } else {
      children.add(RichText(text: parseInlineMarkdown(line, base)));
    }
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
}

// ================= XUẤT FILE =================

String _escapeXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _runXml(String text, {bool bold = false, bool italic = false, bool underline = false, int? size}) {
  if (text.isEmpty) return '';
  final buf = StringBuffer('<w:r>');
  if (bold || italic || underline || size != null) {
    buf.write('<w:rPr>');
    if (bold) buf.write('<w:b/>');
    if (italic) buf.write('<w:i/>');
    if (underline) buf.write('<w:u w:val="single"/>');
    if (size != null) buf.write('<w:sz w:val="$size"/>');
    buf.write('</w:rPr>');
  }
  buf.write('<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r>');
  return buf.toString();
}

String _inlineRuns(String text, {bool forceBold = false, int? size}) {
  final buf = StringBuffer();
  final regex = RegExp(r'(\*\*(.+?)\*\*)|(\*(.+?)\*)|(__(.+?)__)');
  var lastEnd = 0;
  for (final m in regex.allMatches(text)) {
    if (m.start > lastEnd) {
      buf.write(_runXml(text.substring(lastEnd, m.start), bold: forceBold, size: size));
    }
    if (m.group(2) != null) {
      buf.write(_runXml(m.group(2)!, bold: true, size: size));
    } else if (m.group(4) != null) {
      buf.write(_runXml(m.group(4)!, italic: true, bold: forceBold, size: size));
    } else if (m.group(6) != null) {
      buf.write(_runXml(m.group(6)!, underline: true, bold: forceBold, size: size));
    }
    lastEnd = m.end;
  }
  if (lastEnd < text.length) {
    buf.write(_runXml(text.substring(lastEnd), bold: forceBold, size: size));
  }
  return buf.toString();
}

String _markdownToWordXml(String markdown) {
  final buf = StringBuffer();
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      buf.write('<w:p/>');
      continue;
    }
    if (trimmed.startsWith('# ')) {
      buf.write('<w:p>${_inlineRuns(trimmed.substring(2), forceBold: true, size: 48)}</w:p>');
    } else if (trimmed.startsWith('## ')) {
      buf.write('<w:p>${_inlineRuns(trimmed.substring(3), forceBold: true, size: 36)}</w:p>');
    } else if (trimmed.startsWith('### ')) {
      buf.write('<w:p>${_inlineRuns(trimmed.substring(4), forceBold: true, size: 30)}</w:p>');
    } else {
      buf.write('<w:p>${_inlineRuns(line)}</w:p>');
    }
  }
  return buf.toString();
}

/// Sinh file DOCX hoàn chỉnh trong bộ nhớ (ZIP + OOXML).
Uint8List generateDocx(String title, String markdownContent) {
  final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
${_markdownToWordXml(markdownContent)}
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
</w:body>
</w:document>''';

  final contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  final rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('word/document.xml', documentXml);

  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

String generateTxt(String title, String content) {
  return '$title\n\n${stripMarkdown(content)}';
}

String generateMarkdown(String title, String content) {
  return '# $title\n\n$content';
}

String generateHtml(String title, String markdownContent) {
  final html = StringBuffer();
  for (final line in markdownContent.split('\n')) {
    final t = line.trimLeft();
    if (t.isEmpty) { html.write('<p></p>\n'); continue; }
    if (t.startsWith('# ')) {
      html.write('<h1>${_escapeXml(t.substring(2))}</h1>\n');
    } else if (t.startsWith('## ')) {
      html.write('<h2>${_escapeXml(t.substring(3))}</h2>\n');
    } else if (t.startsWith('### ')) {
      html.write('<h3>${_escapeXml(t.substring(4))}</h3>\n');
    } else {
      var s = _escapeXml(line);
      s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
      s = s.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => '<em>${m.group(1)}</em>');
      s = s.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => '<u>${m.group(1)}</u>');
      html.write('<p>$s</p>\n');
    }
  }
  return '''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>${_escapeXml(title)}</title>
<style>body{font-family:Georgia,serif;max-width:800px;margin:40px auto;padding:20px;line-height:1.7;color:#222}h1{border-bottom:2px solid #333;padding-bottom:8px}</style>
</head><body><h1>${_escapeXml(title)}</h1>$html</body></html>''';
}

enum ExportFormat { docx, txt, markdown, html }

extension ExportFormatExt on ExportFormat {
  String get label => switch (this) {
        ExportFormat.docx => 'Word (.docx)',
        ExportFormat.txt => 'Văn bản (.txt)',
        ExportFormat.markdown => 'Markdown (.md)',
        ExportFormat.html => 'HTML (.html)',
      };
  String get extension => switch (this) {
        ExportFormat.docx => 'docx',
        ExportFormat.txt => 'txt',
        ExportFormat.markdown => 'md',
        ExportFormat.html => 'html',
      };
  String get mimeType => switch (this) {
        ExportFormat.docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.txt => 'text/plain',
        ExportFormat.markdown => 'text/markdown',
        ExportFormat.html => 'text/html',
      };
}

/// Sinh nội dung file theo định dạng.
Uint8List buildExportBytes(ExportFormat format, String title, String content) {
  switch (format) {
    case ExportFormat.docx:
      return generateDocx(title, content);
    case ExportFormat.txt:
      return Uint8List.fromList(utf8.encode(generateTxt(title, content)));
    case ExportFormat.markdown:
      return Uint8List.fromList(utf8.encode(generateMarkdown(title, content)));
    case ExportFormat.html:
      return Uint8List.fromList(utf8.encode(generateHtml(title, content)));
  }
}

/// Lưu file tạm và mở hệ thống chia sẻ — đây chính là cách "xuất file".
Future<void> exportAndShare(BuildContext context, ExportFormat format, String title, String content) async {
  try {
    final bytes = buildExportBytes(format, title, content);
    final dir = await getTemporaryDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[^\w\s\-À-ỹ]'), '').trim().replaceAll(' ', '_');
    final fileName = '${safeTitle.isEmpty ? 'novel' : safeTitle}_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    if (!context.mounted) return;
    await Share.shareXFiles([XFile(file.path, mimeType: format.mimeType)], subject: title);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: Colors.redAccent),
    );
  }
}

// ================= MODEL =================

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.isPinned = false,
    required this.words,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final bool isPinned;
  final int words;
  final DateTime updatedAt;

  Note copyWith({
    String? title, String? content, bool? isPinned, int? words, DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      isPinned: isPinned ?? this.isPinned,
      words: words ?? this.words,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

List<Note> _sampleNotes() {
  final now = DateTime.now();
  const welcome =
      'Chào mừng bạn đến với **Novel App**!\n\nNhấn nút cộng ở góc dưới để tạo bài viết mới, hoặc nhấn vào bài này để chỉnh sửa. Nhấn giữ một bài viết để xóa.\n\n## Mẹo dùng nhanh\n- Dùng thanh công cụ để in đậm, in nghiêng, gạch chân, H1, H2.\n- Bấm ngôi sao để mở menu cài đặt và xuất file DOCX.';
  const chapter =
      '# Chương 1: Khởi hành\n\nArista Valerius đứng trên đỉnh ngọn đồi nhìn xuống thung lũng sương mù. Gió lạnh mang theo hương thông, thổi tung mái tóc bạc của cô. Phía chân trời, ánh bình minh đầu tiên đang nhuộm hồng những đỉnh núi xa.';
  return [
    Note(
      id: '1', title: 'Ý tưởng tiểu thuyết mới', content: welcome,
      isPinned: true, words: countWords(stripMarkdown(welcome)),
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
    Note(
      id: '2', title: 'Con đường của ánh sáng - Chương 1', content: chapter,
      words: countWords(stripMarkdown(chapter)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
  ];
}

// ================= LƯU TRỮ (SharedPreferences) =================

class Settings {
  static const _kThemeIndex = 'themeIndex';
  static const _kDailyGoal = 'dailyGoal';

  int themeIndex;
  int dailyGoal;

  Settings({this.themeIndex = 0, this.dailyGoal = 500});

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeIndex = prefs.getInt(_kThemeIndex) ?? 0;
    dailyGoal = prefs.getInt(_kDailyGoal) ?? 500;
  }

  Future<void> saveThemeIndex(int value) async {
    themeIndex = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeIndex, value);
  }

  Future<void> saveDailyGoal(int value) async {
    dailyGoal = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyGoal, value);
  }
}

class StreakService {
  static const _kLastDate = 'streak_last_date';
  static const _kCount = 'streak_count';

  int count = 0;
  DateTime? lastDate;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    count = prefs.getInt(_kCount) ?? 0;
    final iso = prefs.getString(_kLastDate);
    lastDate = iso != null ? DateTime.tryParse(iso) : null;

    // Nếu đã quá 1 ngày không viết → streak đứt
    if (lastDate != null) {
      final diff = dateOnly(DateTime.now()).difference(dateOnly(lastDate!)).inDays;
      if (diff > 1) {
        count = 0;
        await prefs.setInt(_kCount, 0);
      }
    }
  }

  /// Trả về true nếu vừa check-in hôm nay (lần đầu).
  Future<bool> checkInToday() async {
    final today = dateOnly(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    if (lastDate != null && dateOnly(lastDate!) == today) return false;

    if (lastDate != null) {
      final diff = today.difference(dateOnly(lastDate!)).inDays;
      count = diff == 1 ? count + 1 : 1;
    } else {
      count = 1;
    }
    lastDate = DateTime.now();
    await prefs.setInt(_kCount, count);
    await prefs.setString(_kLastDate, lastDate!.toIso8601String());
    return true;
  }

  bool get hasCheckedInToday {
    if (lastDate == null) return false;
    return dateOnly(lastDate!) == dateOnly(DateTime.now());
  }
}

// ================= ROOT =================

class NovelApp extends StatefulWidget {
  const NovelApp({super.key});
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  final Settings _settings = Settings();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _settings.load();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Color get _themeColor => kThemeColors[_settings.themeIndex % kThemeColors.length];

  void _setThemeIndex(int i) {
    setState(() => _settings.saveThemeIndex(i));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(backgroundColor: kBg, body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'Novel App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        primaryColor: _themeColor,
        colorScheme: ColorScheme.dark(primary: _themeColor),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: HomeScreen(
        settings: _settings,
        themeColor: _themeColor,
        onThemeIndexChanged: _setThemeIndex,
      ),
    );
  }
}

// ================= MÀN HÌNH CHÍNH =================

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.themeColor,
    required this.onThemeIndexChanged,
  });

  final Settings settings;
  final Color themeColor;
  final ValueChanged<int> onThemeIndexChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridMode = true;
  String _searchQuery = '';
  int _wordsToday = 0;
  DateTime _goalDay = dateOnly(DateTime.now());
  final List<Note> _notes = _sampleNotes();
  final StreakService _streak = StreakService();
  bool _streakLoaded = false;

  int get _dailyGoal => widget.settings.dailyGoal;
  int get _todayWords => dateOnly(DateTime.now()) == _goalDay ? _wordsToday : 0;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    await _streak.load();
    if (!mounted) return;
    setState(() => _streakLoaded = true);
  }

  void _addWordsToday(int delta) {
    final today = dateOnly(DateTime.now());
    if (today != _goalDay) {
      _goalDay = today;
      _wordsToday = 0;
    }
    final next = _wordsToday + delta;
    _wordsToday = next < 0 ? 0 : next;
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Icon(Icons.bolt, color: widget.themeColor),
          const SizedBox(width: 8),
          const Text('Azrael Novel App', style: TextStyle(fontSize: 18, color: Colors.white)),
        ]),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            '"App được thiết kế và thực hiện bởi azrael. Hãy trải nghiệm và thả hồn vào từng con chữ."',
            style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Trải nghiệm ngay', style: TextStyle(color: widget.themeColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoalDialog() async {
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => _GoalDialog(initialGoal: _dailyGoal, themeColor: widget.themeColor),
    );
    if (goal == null || !mounted) return;
    await widget.settings.saveDailyGoal(goal);
    setState(() {});
  }

  Future<void> _confirmDelete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Xóa bài viết?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('"${note.title}" sẽ bị xóa vĩnh viễn.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _notes.removeWhere((n) => n.id == note.id));
  }

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => EditorScreen(note: note, themeColor: widget.themeColor)),
    );
    if (result == null || !mounted) return;

    setState(() {
      final i = _notes.indexWhere((n) => n.id == result.id);
      if (i >= 0) {
        _addWordsToday(result.words - _notes[i].words);
        _notes[i] = result;
      } else {
        _addWordsToday(result.words);
        _notes.add(result);
      }
      _sortNotes();
    });

    // Streak: check-in nếu đã viết được gì đó
    if (result.words > 0) {
      final newlyChecked = await _streak.checkInToday();
      if (newlyChecked && mounted) {
        setState(() {});
      }
    }

    // Nhắc nghỉ ngơi nếu vượt mục tiêu
    if (_dailyGoal > 0 && _todayWords > _dailyGoal && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showRestReminder();
      });
    }
  }

  void _showRestReminder() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Icon(Icons.self_improvement, color: widget.themeColor),
          const SizedBox(width: 8),
          const Text('Nghỉ ngơi chút nhé!', style: TextStyle(fontSize: 16, color: Colors.white)),
        ]),
        content: Text(
          'Bạn đã viết $_todayWords từ hôm nay, vượt mục tiêu $_dailyGoal từ rồi đó. '
          'Hãy đứng dậy, uống chút nước và thư giãn đôi mắt nhé. Sức khỏe quan trọng hơn con số!',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cảm ơn, mình sẽ nghỉ', style: TextStyle(color: widget.themeColor)),
          ),
        ],
      ),
    );
  }

  void _togglePin(String id) {
    setState(() {
      final i = _notes.indexWhere((n) => n.id == id);
      if (i < 0) return;
      _notes[i] = _notes[i].copyWith(isPinned: !_notes[i].isPinned);
      _sortNotes();
    });
  }

  void _sortNotes() {
    _notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byDate = b.updatedAt.compareTo(a.updatedAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsMenuSheet(
        themeColor: widget.themeColor,
        currentThemeIndex: widget.settings.themeIndex,
        onThemeIndexChanged: (i) {
          widget.onThemeIndexChanged(i);
          Navigator.pop(context);
          // Reopen with new color after a tick so theme actually updated
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _openMenu();
          });
        },
        currentGoal: _dailyGoal,
        onGoalChanged: (g) async {
          await widget.settings.saveDailyGoal(g);
          if (!mounted) return;
          setState(() {});
        },
        streak: _streak,
        streakLoaded: _streakLoaded,
        onExport: _openExportSheet,
      ),
    );
  }

  void _openExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportSheet(
        themeColor: widget.themeColor,
        notes: _notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _notes.where((n) {
      final plain = stripMarkdown(n.content).toLowerCase();
      return n.title.toLowerCase().contains(q) || plain.contains(q);
    }).toList();

    final today = _todayWords;
    final ratio = _dailyGoal > 0 ? today / _dailyGoal : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;
    final exceeded = _dailyGoal > 0 && today > _dailyGoal;

    return Scaffold(
      body: Stack(
        children: [
          _AmbientBackground(themeColor: widget.themeColor),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(today, progress, exceeded),
                  const SizedBox(height: 16),
                  _buildSearchField(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildNotesView(filtered)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.themeColor,
        tooltip: 'Viết bài mới',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildHeader(int todayWords, double progress, bool exceeded) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Giới thiệu',
              icon: Icon(Icons.bolt, color: widget.themeColor, size: 20),
              onPressed: _showAboutDialog,
            ),
            // Nút ngôi sao giờ mở MENU (đúng như yêu cầu)
            IconButton(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Menu cài đặt',
              icon: Icon(Icons.star_rounded, color: widget.themeColor, size: 20),
              onPressed: _openMenu,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _showGoalDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: exceeded ? Colors.orangeAccent.fade(0.12) : Colors.white.fade(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: exceeded ? Colors.orangeAccent.fade(0.4) : Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exceeded ? 'Đã vượt mục tiêu — nghỉ chút nhé!' : 'Chào mừng đã đến với app',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: exceeded ? Colors.orangeAccent : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Hôm nay: $todayWords / $_dailyGoal từ',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      exceeded ? Colors.orangeAccent : widget.themeColor,
                    ),
                    minHeight: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.fade(0.06),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: IconButton(
            tooltip: _isGridMode ? 'Xem dạng danh sách' : 'Xem dạng lưới',
            icon: Icon(_isGridMode ? Icons.grid_view : Icons.view_agenda, size: 18),
            onPressed: () => setState(() => _isGridMode = !_isGridMode),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: 'Tìm kiếm bài viết...',
        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white38),
        filled: true,
        fillColor: Colors.white.fade(0.05),
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildNotesView(List<Note> notes) {
    if (notes.isEmpty) {
      final message = _notes.isEmpty
          ? 'Chưa có bài viết nào.\nNhấn nút cộng để bắt đầu viết.'
          : 'Không tìm thấy bài viết phù hợp.';
      return Center(
        child: Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, height: 1.5)),
      );
    }
    const listPad = EdgeInsets.only(bottom: 88);

    if (_isGridMode) {
      return GridView.builder(
        padding: listPad,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260, mainAxisExtent: 168,
          crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: notes.length,
        itemBuilder: (_, i) => _buildNoteCard(notes[i], key: ValueKey(notes[i].id)),
      );
    }
    return ListView.builder(
      padding: listPad,
      itemCount: notes.length,
      itemBuilder: (_, i) => _buildNoteCard(notes[i], key: ValueKey(notes[i].id)),
    );
  }

  Widget _buildNoteCard(Note note, {Key? key}) {
    final plain = stripMarkdown(note.content);
    final contentText = Text(
      plain.isEmpty ? '(Chưa có nội dung)' : previewText(plain),
      maxLines: _isGridMode ? 3 : 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white60, fontSize: 13),
    );

    return GestureDetector(
      key: key,
      onTap: () => _openEditor(note),
      onLongPress: () => _confirmDelete(note),
      child: Container(
        margin: EdgeInsets.only(bottom: _isGridMode ? 0 : 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.fade(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: note.isPinned ? widget.themeColor.fade(0.5) : Colors.white10,
          ),
        ),
        child: Column(
          mainAxisSize: _isGridMode ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Không có tiêu đề' : note.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: note.isPinned ? 'Bỏ ghim' : 'Ghim bài viết',
                  icon: Icon(Icons.push_pin, size: 16,
                      color: note.isPinned ? Colors.amber : Colors.white24),
                  onPressed: () => _togglePin(note.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isGridMode) Expanded(child: contentText) else contentText,
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${note.words} từ',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(formatDate(note.updatedAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= NỀN LOANG ĐẸP HƠN =================

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({required this.themeColor});
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Quầng sáng chính phía trên-trái
      Positioned(
        top: -260, left: -180,
        child: _Glow(color: themeColor, size: 620, intensity: 0.35),
      ),
      // Quầng phụ phía dưới-phải
      Positioned(
        bottom: -260, right: -200,
        child: _Glow(color: themeColor, size: 560, intensity: 0.28),
      ),
      // Điểm nhấn nhỏ phía trên-phải
      Positioned(
        top: 80, right: -120,
        child: _Glow(color: themeColor, size: 280, intensity: 0.12),
      ),
      // Điểm nhấn nhỏ phía dưới-trái
      Positioned(
        bottom: 60, left: -100,
        child: _Glow(color: themeColor, size: 240, intensity: 0.1),
      ),
      // Lớp phủ tối để không bị chói
      Container(color: Colors.black.fade(0.15)),
    ]);
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.intensity});
  final Color color;
  final double size;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.fade(intensity),
              color.fade(intensity * 0.5),
              color.fade(intensity * 0.15),
              Colors.transparent,
            ],
            stops: const [0.0, 0.35, 0.65, 1.0],
          ),
        ),
      ),
    );
  }
}

// ================= MENU CÀI ĐẶT (BOTTOM SHEET) =================

class _SettingsMenuSheet extends StatelessWidget {
  const _SettingsMenuSheet({
    required this.themeColor,
    required this.currentThemeIndex,
    required this.onThemeIndexChanged,
    required this.currentGoal,
    required this.onGoalChanged,
    required this.streak,
    required this.streakLoaded,
    required this.onExport,
  });

  final Color themeColor;
  final int currentThemeIndex;
  final ValueChanged<int> onThemeIndexChanged;
  final int currentGoal;
  final ValueChanged<int> onGoalChanged;
  final StreakService streak;
  final bool streakLoaded;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121218),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.star_rounded, color: themeColor, size: 28),
              const SizedBox(width: 10),
              const Text('Cài đặt & Công cụ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
            const SizedBox(height: 24),

            // --- Màu chủ đề ---
            _SectionTitle(icon: Icons.palette_outlined, text: 'Màu chủ đề', color: themeColor),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12,
              children: List.generate(kThemeColors.length, (i) {
                final c = kThemeColors[i];
                final selected = i == currentThemeIndex;
                return GestureDetector(
                  onTap: () => onThemeIndexChanged(i),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: c, shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : Border.all(color: Colors.white24),
                      boxShadow: selected
                          ? [BoxShadow(color: c.fade(0.6), blurRadius: 12)]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 22)
                        : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),

            // --- Mục tiêu hàng ngày ---
            _SectionTitle(icon: Icons.flag_outlined, text: 'Mục tiêu mỗi ngày', color: themeColor),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final newGoal = await showDialog<int>(
                  context: context,
                  builder: (_) => _GoalDialog(initialGoal: currentGoal, themeColor: themeColor),
                );
                if (newGoal != null && context.mounted) {
                  onGoalChanged(newGoal);
                  Navigator.pop(context);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.fade(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18, color: themeColor),
                  const SizedBox(width: 12),
                  Expanded(child: Text('$currentGoal từ/ngày',
                      style: const TextStyle(color: Colors.white, fontSize: 15))),
                  const Text('Đổi', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 28),

            // --- Điểm danh chuỗi ---
            _SectionTitle(icon: Icons.local_fire_department_outlined,
                text: 'Điểm danh chuỗi', color: themeColor),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [themeColor.fade(0.25), themeColor.fade(0.05)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: themeColor.fade(0.4)),
              ),
              child: streakLoaded
                  ? Row(children: [
                      Icon(Icons.local_fire_department,
                          color: Colors.orangeAccent, size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${streak.count} ngày liên tiếp',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(height: 4),
                            Text(
                              streak.hasCheckedInToday
                                  ? 'Hôm nay đã điểm danh ✓'
                                  : 'Viết một bài hôm nay để giữ chuỗi!',
                              style: TextStyle(
                                fontSize: 12,
                                color: streak.hasCheckedInToday
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ])
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
            ),
            const SizedBox(height: 28),

            // --- Xuất file ---
            _SectionTitle(icon: Icons.file_download_outlined,
                text: 'Xuất file', color: themeColor),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                onExport();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.fade(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  Icon(Icons.description_outlined, size: 20, color: themeColor),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Xuất DOCX / TXT / MD / HTML',
                            style: TextStyle(color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        SizedBox(height: 2),
                        Text('Chọn bài viết rồi chia sẻ / lưu về máy',
                            style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ]),
              ),
            ),
            const SizedBox(height: 28),

            // --- Info ---
            Center(
              child: Text(
                'Novel App • bởi azrael',
                style: TextStyle(color: Colors.white.fade(0.3), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}

// ================= SHEET XUẤT FILE =================

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.themeColor, required this.notes});
  final Color themeColor;
  final List<Note> notes;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  Note? _selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.file_download_outlined, color: widget.themeColor, size: 24),
              const SizedBox(width: 10),
              const Text('Xuất file',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
            const SizedBox(height: 16),
            const Text('Chọn bài viết:',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.notes.length,
                itemBuilder: (_, i) {
                  final n = widget.notes[i];
                  final sel = identical(_selected, n) || (_selected?.id == n.id);
                  return InkWell(
                    onTap: () => setState(() => _selected = n),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? widget.themeColor.fade(0.15) : Colors.white.fade(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? widget.themeColor.fade(0.6) : Colors.white12,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          size: 18,
                          color: sel ? widget.themeColor : Colors.white38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            n.title.isEmpty ? '(Không tiêu đề)' : n.title,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('Chọn định dạng:',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            ...ExportFormat.values.map((f) {
              final enabled = _selected != null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: enabled
                      ? () async {
                          final note = _selected!;
                          Navigator.pop(context);
                          final title = note.title.isEmpty ? 'Bài viết' : note.title;
                          await exportAndShare(context, f, title, note.content);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: enabled
                          ? Colors.white.fade(0.06)
                          : Colors.white.fade(0.02),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: enabled ? Colors.white24 : Colors.white10,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        switch (f) {
                          ExportFormat.docx => Icons.description,
                          ExportFormat.txt => Icons.text_snippet_outlined,
                          ExportFormat.markdown => Icons.code,
                          ExportFormat.html => Icons.web_outlined,
                        },
                        color: enabled ? widget.themeColor : Colors.white24,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          f.label,
                          style: TextStyle(
                            color: enabled ? Colors.white : Colors.white24,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (enabled)
                        const Icon(Icons.chevron_right, color: Colors.white38),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              _selected == null ? 'Chọn một bài viết để tiếp tục.' : 'File sẽ được tạo và mở bảng chia sẻ.',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= HỘP THOẠI MỤC TIÊU =================

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.initialGoal, required this.themeColor});
  final int initialGoal;
  final Color themeColor;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialGoal.toString());
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Nhập số từ lớn hơn 0');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Mục tiêu viết hàng ngày',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.fade(0.08),
          errorText: _error,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixText: 'từ',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Lưu', style: TextStyle(color: widget.themeColor)),
        ),
      ],
    );
  }
}

// ================= EDITOR =================

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.note, required this.themeColor});
  final Note? note;
  final Color themeColor;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _contentFocus;
  int _wordCount = 0;
  String _lastCountedText = '';
  bool _previewMode = false;

  // Undo stack — tự quản lý vì TextField không có sẵn undo gọn.
  final List<TextEditingValue> _undoStack = [];
  Timer? _undoDebounce;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _contentFocus = FocusNode();
    _lastCountedText = _contentController.text;
    _wordCount = countWords(stripMarkdown(_lastCountedText));
    _contentController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    final text = _contentController.text;
    if (text == _lastCountedText) return;
    _lastCountedText = text;

    // Cập nhật số từ luôn (kể cả khi đang composition)
    final count = countWords(stripMarkdown(text));
    if (count != _wordCount) {
      setState(() => _wordCount = count);
    }

    // Undo debounce: nhóm các lần gõ nhanh vào 1 mốc undo
    _undoDebounce?.cancel();
    _undoDebounce = Timer(const Duration(milliseconds: 800), () {
      if (_undoStack.isEmpty || _undoStack.last.text != _contentController.text) {
        _pushUndo();
      }
    });
  }

  void _pushUndo() {
    _undoStack.add(_contentController.value);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final prev = _undoStack.removeLast();
    _contentController.value = prev;
    setState(() {});
  }

  /// Chèn markdown bao quanh vùng chọn.
  void _applyWrap(String before, String after) {
    _pushUndo();
    final sel = _contentController.selection;
    final text = _contentController.text;

    if (!sel.isValid) {
      // Không có selection, chèn cặp dấu và đặt con trỏ ở giữa
      final insert = before + after;
      final newPos = _contentController.selection.baseOffset;
      if (newPos < 0) return;
      final newText = text.substring(0, newPos) + insert + text.substring(newPos);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newPos + before.length),
      );
      return;
    }

    final selected = text.substring(sel.start, sel.end);
    final newText = text.substring(0, sel.start) +
        before + selected + after +
        text.substring(sel.end);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: sel.start + before.length,
        extentOffset: sel.end + before.length,
      ),
    );
  }

  /// Thêm/toggle prefix ở đầu dòng hiện tại (cho H1, H2).
  void _applyLinePrefix(String prefix) {
    _pushUndo();
    final text = _contentController.text;
    final sel = _contentController.selection;
    final cursor = sel.isValid ? sel.baseOffset : text.length;
    final lineStart = text.lastIndexOf('\n', cursor > 0 ? cursor - 1 : 0) + 1;

    // Kiểm tra dòng đã có prefix chưa
    final existing = text.substring(lineStart);
    if (existing.startsWith(prefix)) {
      // Toggle: bỏ prefix
      final newText = text.substring(0, lineStart) +
          text.substring(lineStart + prefix.length);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: (cursor - prefix.length).clamp(0, newText.length),
        ),
      );
    } else {
      // Chèn prefix
      final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor + prefix.length),
      );
    }
  }

  void _saveAndExit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final original = widget.note;

    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final finalTitle = title.isEmpty ? 'Bài viết mới' : title;
    if (original != null &&
        original.title == finalTitle &&
        original.content == content) {
      Navigator.of(context).pop();
      return;
    }

    final now = DateTime.now();
    final saved = Note(
      id: original?.id ?? now.microsecondsSinceEpoch.toString(),
      title: finalTitle,
      content: content,
      isPinned: original?.isPinned ?? false,
      words: countWords(stripMarkdown(content)),
      updatedAt: now,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  void dispose() {
    _undoDebounce?.cancel();
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _contentController.selection.isValid &&
        !_contentController.selection.isCollapsed;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Lưu và quay lại',
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: _saveAndExit,
          ),
          title: Text(
            _previewMode ? 'Xem trước' : 'Soạn thảo',
            style: const TextStyle(fontSize: 15, color: Colors.white70),
          ),
          actions: [
            IconButton(
              tooltip: _previewMode ? 'Chỉnh sửa' : 'Xem trước',
              icon: Icon(
                _previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                color: Colors.white70,
              ),
              onPressed: () => setState(() => _previewMode = !_previewMode),
            ),
            IconButton(
              tooltip: 'Lưu',
              icon: Icon(Icons.check, color: widget.themeColor, size: 28),
              onPressed: _saveAndExit,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _previewMode ? _buildPreview() : _buildEditor()),
              if (!_previewMode) _buildToolbar(hasSelection),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            autofocus: widget.note == null,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white,
            ),
            decoration: const InputDecoration(
              hintText: 'Tiêu đề chương / bài viết...',
              hintStyle: TextStyle(color: Colors.white30),
              border: InputBorder.none,
            ),
          ),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.themeColor.fade(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_wordCount từ',
                style: TextStyle(
                  color: widget.themeColor, fontSize: 12, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_wordCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                '~${(_wordCount / 200).ceil()} phút đọc',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ]),
          const Divider(color: Colors.white10, height: 24),
          Expanded(
            child: TextField(
              controller: _contentController,
              focusNode: _contentFocus,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, color: kWhite90, height: 1.6),
              decoration: const InputDecoration(
                hintText: 'Bắt đầu đặt bút thả hồn vào câu chuyện...\n\nDùng thanh công cụ bên dưới để định dạng.',
                hintStyle: TextStyle(color: Colors.white24),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleController.text.isEmpty ? '(Chưa có tiêu đề)' : _titleController.text,
            style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.themeColor.fade(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_wordCount từ',
                style: TextStyle(
                  color: widget.themeColor, fontSize: 12, fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]),
          const Divider(color: Colors.white10, height: 28),
          renderMarkdown(_contentController.text, widget.themeColor),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool hasSelection) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121218),
        border: Border(top: BorderSide(color: Colors.white.fade(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _ToolbarBtn(
              icon: Icons.undo,
              tooltip: 'Hoàn tác',
              themeColor: widget.themeColor,
              enabled: _undoStack.isNotEmpty,
              onTap: _undo,
            ),
            _Divider(),
            _ToolbarTextBtn(
              label: 'B', bold: true,
              tooltip: 'In đậm',
              themeColor: widget.themeColor,
              onTap: () => _applyWrap('**', '**'),
            ),
            _ToolbarTextBtn(
              label: 'I', italic: true,
              tooltip: 'In nghiêng',
              themeColor: widget.themeColor,
              onTap: () => _applyWrap('*', '*'),
            ),
            _ToolbarTextBtn(
              label: 'U', underline: true,
              tooltip: 'Gạch chân',
              themeColor: widget.themeColor,
              onTap: () => _applyWrap('__', '__'),
            ),
            _Divider(),
            _ToolbarTextBtn(
              label: 'H1',
              tooltip: 'Tiêu đề lớn',
              themeColor: widget.themeColor,
              onTap: () => _applyLinePrefix('# '),
            ),
            _ToolbarTextBtn(
              label: 'H2',
              tooltip: 'Tiêu đề vừa',
              themeColor: widget.themeColor,
              onTap: () => _applyLinePrefix('## '),
            ),
            _ToolbarTextBtn(
              label: 'H3',
              tooltip: 'Tiêu đề nhỏ',
              themeColor: widget.themeColor,
              onTap: () => _applyLinePrefix('### '),
            ),
            _Divider(),
            _ToolbarBtn(
              icon: Icons.short_text,
              tooltip: 'Chèn dòng trống',
              themeColor: widget.themeColor,
              onTap: () => _applyWrap('\n\n', ''),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    required this.themeColor,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String tooltip;
  final Color themeColor;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
          child: Icon(icon,
              size: 20, color: enabled ? Colors.white70 : Colors.white24),
        ),
      ),
    );
  }
}

class _ToolbarTextBtn extends StatelessWidget {
  const _ToolbarTextBtn({
    required this.label,
    required this.tooltip,
    required this.themeColor,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });
  final String label;
  final String tooltip;
  final Color themeColor;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white12,
    );
  }
}
