import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Text;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const NovelApp());
}

// ================= TIỆN ÍCH =================

/// Các màu chủ đề, bấm biểu tượng ngôi sao để đổi lần lượt.
const List<Color> kThemeColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFA855F7),
];

/// Màu chữ trắng đục 90% (Flutter không có sẵn `Colors.white90`).
const Color kWhite90 = Color(0xE6FFFFFF);

extension ColorFade on Color {
  /// Trả về màu này với độ đục [opacity] (0.0 - 1.0).
  /// Dùng `withAlpha` để chạy tốt trên mọi phiên bản Flutter,
  /// không bị cảnh báo `withOpacity` như các bản mới.
  Color fade(double opacity) => withAlpha((opacity * 255).round());
}

/// Đếm từ theo mọi nhóm ký tự không phải khoảng trắng. Cách này xử lý ổn
/// định khoảng trắng Unicode, xuống dòng và văn bản dài khi gõ trực tiếp.
int countWords(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
}

bool isQuillDelta(String content) {
  try {
    final decoded = jsonDecode(content);
    return decoded is List && decoded.every((item) => item is Map && item.containsKey('insert'));
  } catch (_) {
    return false;
  }
}

/// Nội dung cũ vốn là text thuần; nội dung mới được lưu dạng Quill Delta JSON.
String notePlainText(String content) {
  if (!isQuillDelta(content)) return content;
  try {
    final decoded = jsonDecode(content) as List<dynamic>;
    return Document.fromJson(decoded).toPlainText().trimRight();
  } catch (_) {
    return content;
  }
}

Document documentFromStoredContent(String? content) {
  if (content == null || content.isEmpty) return Document();
  if (isQuillDelta(content)) {
    try {
      return Document.fromJson(jsonDecode(content) as List<dynamic>);
    } catch (_) {
      // Nếu dữ liệu cũ bị lỗi định dạng, mở lại dưới dạng văn bản thuần.
    }
  }
  return Document.fromJson(<dynamic>[<String, dynamic>{'insert': '$content\n'}]);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

String _storedContentForJson(String content) {
  if (isQuillDelta(content)) return content;
  return jsonEncode(<dynamic>[<String, dynamic>{'insert': '$content\n'}]);
}

String _markdownForContent(String content) {
  if (!isQuillDelta(content)) return content;
  try {
    final ops = jsonDecode(content) as List<dynamic>;
    final out = StringBuffer();
    var line = StringBuffer();

    String inline(String text, Map<String, dynamic> attrs) {
      var value = text;
      if (attrs['code'] == true) value = '`$value`';
      if (attrs['bold'] == true) value = '**$value**';
      if (attrs['italic'] == true) value = '*$value*';
      if (attrs['underline'] == true) value = '<u>$value</u>';
      if (attrs['strike'] == true) value = '~~$value~~';
      if (attrs['link'] is String) value = '[$value](${attrs['link']})';
      return value;
    }

    for (final raw in ops) {
      if (raw is! Map || raw['insert'] is! String) continue;
      final inserted = raw['insert'] as String;
      final rawAttrs = raw['attributes'];
      final attrs = rawAttrs is Map<String, dynamic>
          ? rawAttrs
          : (rawAttrs is Map ? Map<String, dynamic>.from(rawAttrs) : <String, dynamic>{});
      var segment = StringBuffer();
      for (final rune in inserted.runes) {
        final char = String.fromCharCode(rune);
        if (char == '\n') {
          final pending = segment.toString();
          if (pending.isNotEmpty) line.write(inline(pending, attrs));
          final blockAttrs = attrs;
          final header = blockAttrs['header'];
          final text = line.toString();
          if (header is int && header >= 1 && header <= 6 && text.isNotEmpty) {
            out.writeln('${List<String>.filled(header, '#').join()} $text');
          } else if (blockAttrs['list'] == 'bullet' && text.isNotEmpty) {
            out.writeln('- $text');
          } else if (blockAttrs['list'] == 'ordered' && text.isNotEmpty) {
            out.writeln('1. $text');
          } else {
            out.writeln(text);
          }
          line = StringBuffer();
          segment = StringBuffer();
        } else {
          segment.write(char);
        }
      }
      final pending = segment.toString();
      if (pending.isNotEmpty) line.write(inline(pending, attrs));
    }
    if (line.isNotEmpty) out.write(line.toString());
    return out.toString().trimRight();
  } catch (_) {
    return notePlainText(content);
  }
}

String _htmlForContent(String content) {
  if (!isQuillDelta(content)) {
    return content.split('\n').map((line) => '<p>${htmlEscape.convert(line)}</p>').join();
  }
  try {
    final ops = jsonDecode(content) as List<dynamic>;
    final out = StringBuffer();
    var line = StringBuffer();

    String inlineHtml(String text, Map<String, dynamic> attrs) {
      var value = htmlEscape.convert(text);
      if (attrs['code'] == true) value = '<code>$value</code>';
      if (attrs['bold'] == true) value = '<strong>$value</strong>';
      if (attrs['italic'] == true) value = '<em>$value</em>';
      if (attrs['underline'] == true) value = '<u>$value</u>';
      if (attrs['strike'] == true) value = '<del>$value</del>';
      if (attrs['link'] is String) value = '<a href="${htmlEscape.convert(attrs['link'] as String)}">$value</a>';
      return value;
    }

    for (final raw in ops) {
      if (raw is! Map || raw['insert'] is! String) continue;
      final inserted = raw['insert'] as String;
      final rawAttrs = raw['attributes'];
      final attrs = rawAttrs is Map<String, dynamic>
          ? rawAttrs
          : (rawAttrs is Map ? Map<String, dynamic>.from(rawAttrs) : <String, dynamic>{});
      var segment = StringBuffer();
      for (final rune in inserted.runes) {
        final char = String.fromCharCode(rune);
        if (char == '\n') {
          final pending = segment.toString();
          if (pending.isNotEmpty) line.write(inlineHtml(pending, attrs));
          final text = line.toString();
          final header = attrs['header'];
          if (header is int && header >= 1 && header <= 6) {
            out.write('<h$header>$text</h$header>');
          } else if (attrs['list'] == 'bullet') {
            out.write('<p class="bullet">&#8226; $text</p>');
          } else if (attrs['list'] == 'ordered') {
            out.write('<p class="ordered">1. $text</p>');
          } else if (attrs['blockquote'] == true) {
            out.write('<blockquote>$text</blockquote>');
          } else {
            out.write('<p>$text</p>');
          }
          line = StringBuffer();
          segment = StringBuffer();
        } else {
          segment.write(char);
        }
      }
      final pending = segment.toString();
      if (pending.isNotEmpty) line.write(inlineHtml(pending, attrs));
    }
    if (line.isNotEmpty) out.write('<p>${line.toString()}</p>');
    return out.toString();
  } catch (_) {
    return notePlainText(content).split('\n').map((line) => '<p>${htmlEscape.convert(line)}</p>').join();
  }
}

String _docxRun(String text, Map<String, dynamic> attrs) {
  final properties = StringBuffer();
  if (attrs['bold'] == true) properties.write('<w:b/>');
  if (attrs['italic'] == true) properties.write('<w:i/>');
  if (attrs['underline'] == true) properties.write('<w:u w:val="single"/>');
  if (attrs['strike'] == true) properties.write('<w:strike/>');
  if (attrs['code'] == true) properties.write('<w:rStyle w:val="CodeChar"/>');
  final color = attrs['color'];
  if (color is String) {
    final safeColor = color.replaceAll('#', '').toUpperCase();
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(safeColor)) properties.write('<w:color w:val="$safeColor"/>');
  }
  final rPr = properties.isEmpty ? '' : '<w:rPr>${properties.toString()}</w:rPr>';
  return '<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r>';
}

String _docxParagraphsForNote(Note note) {
  final body = StringBuffer();
  body.write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t xml:space="preserve">${_xmlEscape(note.title)}</w:t></w:r></w:p>');
  if (!isQuillDelta(note.content)) {
    for (final line in notePlainText(note.content).split('\n')) {
      body.write('<w:p><w:r><w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>');
    }
    return body.toString();
  }

  try {
    final ops = jsonDecode(note.content) as List<dynamic>;
    var paragraphRuns = StringBuffer();
    for (final raw in ops) {
      if (raw is! Map || raw['insert'] is! String) continue;
      final inserted = raw['insert'] as String;
      final rawAttrs = raw['attributes'];
      final attrs = rawAttrs is Map<String, dynamic>
          ? rawAttrs
          : (rawAttrs is Map ? Map<String, dynamic>.from(rawAttrs) : <String, dynamic>{});
      var segment = StringBuffer();
      for (final rune in inserted.runes) {
        final char = String.fromCharCode(rune);
        if (char == '\n') {
          final pending = segment.toString();
          if (pending.isNotEmpty) paragraphRuns.write(_docxRun(pending, attrs));
          final header = attrs['header'];
          final listType = attrs['list'];
          var pPr = '';
          if (header is int && header >= 1 && header <= 3) {
            pPr = '<w:pPr><w:pStyle w:val="Heading$header"/></w:pPr>';
          } else if (listType == 'bullet' || listType == 'ordered') {
            final prefix = listType == 'bullet' ? '• ' : '1. ';
            paragraphRuns = StringBuffer('${_docxRun(prefix, <String, dynamic>{})}${paragraphRuns.toString()}');
          }
          body.write('<w:p>$pPr${paragraphRuns.toString().isEmpty ? '<w:r><w:t></w:t></w:r>' : paragraphRuns.toString()}</w:p>');
          paragraphRuns = StringBuffer();
          segment = StringBuffer();
        } else {
          segment.write(char);
        }
      }
      final pending = segment.toString();
      if (pending.isNotEmpty) paragraphRuns.write(_docxRun(pending, attrs));
    }
    if (paragraphRuns.isNotEmpty) body.write('<w:p>${paragraphRuns.toString()}</w:p>');
  } catch (_) {
    for (final line in notePlainText(note.content).split('\n')) {
      body.write('<w:p><w:r><w:t xml:space="preserve">${_xmlEscape(line)}</w:t></w:r></w:p>');
    }
  }
  return body.toString();
}

List<int> _buildDocxBytes(List<Note> notes) {
  final body = StringBuffer();
  for (final note in notes) {
    body.write(_docxParagraphsForNote(note));
    body.write('<w:p/>');
  }
  body.write('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>');
  final documentXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body.toString()}</w:body></w:document>""";
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  add('[Content_Types].xml', """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>""");
  add('_rels/.rels', """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>""");
  add('word/_rels/document.xml.rels', """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>""");
  add('word/styles.xml', """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="22"/></w:rPr></w:style><w:style w:type="character" w:styleId="CodeChar"><w:name w:val="Code Char"/><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:shd w:fill="F0F0F0"/></w:rPr></w:style></w:styles>""");
  add('word/document.xml', documentXml);
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('Không tạo được tệp DOCX.');
  return encoded;
}

Future<Uint8List> _buildPdfBytes(List<Note> notes) async {
  pw.Font font = pw.Font.helvetica();
  // Android thường có Roboto sẵn; nhúng font này để PDF hiển thị tiếng Việt.
  try {
    final fontFile = File('/system/fonts/Roboto-Regular.ttf');
    if (await fontFile.exists()) {
      final bytes = Uint8List.fromList(await fontFile.readAsBytes());
      font = pw.Font.ttf(ByteData.sublistView(bytes));
    }
  } catch (_) {
    // Nếu không truy cập được font hệ thống, dùng font mặc định của pdf package.
  }
  final pdf = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font);
  pdf.addPage(pw.MultiPage(
    theme: theme,
    build: (context) {
      final widgets = <pw.Widget>[];
      for (final note in notes) {
        widgets.add(pw.Header(level: 0, child: pw.Text(note.title)));
        for (final line in notePlainText(note.content).split('\n')) {
          widgets.add(pw.Paragraph(text: line.isEmpty ? ' ' : line));
        }
        widgets.add(pw.SizedBox(height: 12));
      }
      return widgets;
    },
  ));
  return Uint8List.fromList(await pdf.save());
}

/// Cắt đoạn xem trước để thẻ bài viết không phải dàn trang cả chương dài.
String previewText(String text, {int maxChars = 240}) {
  if (text.length <= maxChars) return text;
  var end = maxChars;
  final last = text.codeUnitAt(end - 1);
  // Không cắt đôi một cặp surrogate (emoji...) vì sẽ gây lỗi hiển thị.
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return text.substring(0, end);
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

// ================= MODEL BÀI VIẾT =================
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
    String? title,
    String? content,
    bool? isPinned,
    int? words,
    DateTime? updatedAt,
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
      'Chào mừng bạn đến với ứng dụng Novel App! Nhấn nút cộng ở góc dưới để '
      'tạo bài viết mới hoặc nhấn vào bài này để chỉnh sửa. Nhấn giữ một bài '
      'viết để xóa.';
  const chapter =
      'Arista Valerius đứng trên đỉnh ngọn đồi nhìn xuống thung lũng sương mù...';
  return [
    Note(
      id: '1',
      title: 'Ý tưởng tiểu thuyết mới',
      content: welcome,
      isPinned: true,
      words: countWords(welcome),
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
    Note(
      id: '2',
      title: 'Con đường của ánh sáng - Chương 1',
      content: chapter,
      words: countWords(chapter),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
  ];
}

// ================= GỐC ỨNG DỤNG =================
class NovelApp extends StatefulWidget {
  const NovelApp({super.key});

  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  Color _themeColor = kThemeColors.first;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getInt('novel_theme_color');
    if (savedValue == null || !mounted) return;
    setState(() => _themeColor = Color(savedValue));
  }

  void _changeThemeColor(Color color) {
    setState(() => _themeColor = color);
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('novel_theme_color', color.value));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Novel App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08080A),
        primaryColor: _themeColor,
        colorScheme: ColorScheme.dark(primary: _themeColor),
      ),
      home: HomeScreen(
        themeColor: _themeColor,
        onThemeChanged: _changeThemeColor,
      ),
    );
  }
}

// ================= MÀN HÌNH CHÍNH =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeColor,
    required this.onThemeChanged,
  });

  final Color themeColor;
  final ValueChanged<Color> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridMode = true;
  int _dailyGoal = 500;
  String _searchQuery = '';
  double _glowIntensity = 0.24;
  int _streak = 0;
  String? _lastCheckIn;
  bool _checkedInToday = false;

  // Bộ đếm từ trong ngày; mục tiêu và chuỗi điểm danh được lưu trên thiết bị.
  int _wordsToday = 0;
  DateTime _goalDay = dateOnly(DateTime.now());

  final List<Note> _notes = _sampleNotes();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey(DateTime.now());
    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final savedLast = prefs.getString('novel_last_checkin');
    var savedStreak = prefs.getInt('novel_checkin_streak') ?? 0;
    if (savedLast != today && savedLast != yesterday) savedStreak = 0;
    if (!mounted) return;
    setState(() {
      _dailyGoal = prefs.getInt('novel_daily_goal') ?? 500;
      _glowIntensity = (prefs.getDouble('novel_glow_intensity') ?? 0.24).clamp(0.05, 0.45).toDouble();
      _streak = savedStreak;
      _lastCheckIn = savedLast;
      _checkedInToday = savedLast == today;
    });
    if (savedStreak != (prefs.getInt('novel_checkin_streak') ?? 0)) {
      await prefs.setInt('novel_checkin_streak', savedStreak);
    }
  }

  int get _todayWords =>
      dateOnly(DateTime.now()) == _goalDay ? _wordsToday : 0;

  void _addWordsToday(int delta) {
    final today = dateOnly(DateTime.now());
    if (today != _goalDay) {
      _goalDay = today;
      _wordsToday = 0;
    }
    final next = _wordsToday + delta;
    _wordsToday = next < 0 ? 0 : next;
  }

  Future<void> _showAppMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15151D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Icon(Icons.star, color: Colors.amber, size: 25),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Menu Novel App', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                  IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close, color: Colors.white54)),
                ]),
                const SizedBox(height: 18),
                const Text('TÙY CHỈNH GIAO DIỆN', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: kThemeColors.map((color) => GestureDetector(
                    onTap: () => widget.onThemeChanged(color),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: widget.themeColor == color ? Colors.white : Colors.white24, width: widget.themeColor == color ? 3 : 1),
                        boxShadow: [BoxShadow(color: color.fade(0.3), blurRadius: 14, spreadRadius: 1)],
                      ),
                      child: widget.themeColor == color ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  const Expanded(child: Text('Độ loang ánh sáng nền', style: TextStyle(color: Colors.white70))),
                  Text('${(_glowIntensity * 100).round()}%', style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.bold)),
                ]),
                Slider(
                  value: _glowIntensity,
                  min: 0.05,
                  max: 0.45,
                  activeColor: widget.themeColor,
                  onChanged: (value) {
                    setState(() => _glowIntensity = value);
                    setSheetState(() {});
                  },
                  onChangeEnd: (value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setDouble('novel_glow_intensity', value);
                  },
                ),
                const Divider(color: Colors.white12, height: 26),
                const Text('MỤC TIÊU VÀ THÓI QUEN', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _menuTile(
                  icon: Icons.flag_outlined,
                  title: 'Mục tiêu viết hằng ngày',
                  subtitle: '$_dailyGoal từ mỗi ngày',
                  color: widget.themeColor,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showGoalDialog();
                  },
                ),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white.fade(0.045), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.orange.fade(0.16), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.local_fire_department, color: Colors.orangeAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Chuỗi điểm danh: $_streak ngày', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_checkedInToday ? 'Hôm nay m đã điểm danh rồi!' : 'Điểm danh hôm nay để giữ chuỗi.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _checkedInToday ? null : () async {
                        await _checkInToday();
                        setSheetState(() {});
                      },
                      style: FilledButton.styleFrom(backgroundColor: widget.themeColor, disabledBackgroundColor: Colors.white12),
                      child: Text(_checkedInToday ? 'Đã điểm danh' : 'Điểm danh'),
                    ),
                  ]),
                ),
                const Divider(color: Colors.white12, height: 30),
                const Text('XUẤT VÀ TIỆN ÍCH', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _menuTile(
                  icon: Icons.file_download_outlined,
                  title: 'Xuất tệp / sao lưu bài viết',
                  subtitle: 'TXT, Markdown, HTML, JSON, CSV, DOCX, PDF',
                  color: widget.themeColor,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showExportDialog();
                  },
                ),
                _menuTile(
                  icon: Icons.info_outline,
                  title: 'Giới thiệu ứng dụng',
                  subtitle: 'Thông tin về Novel App',
                  color: widget.themeColor,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showAboutDialog();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuTile({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: color.fade(0.13), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  Future<void> _checkInToday() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = _dateKey(now);
    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    if (_lastCheckIn == today) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hôm nay m đã điểm danh rồi.')));
      return;
    }
    final nextStreak = _lastCheckIn == yesterday ? _streak + 1 : 1;
    await prefs.setString('novel_last_checkin', today);
    await prefs.setInt('novel_checkin_streak', nextStreak);
    if (!mounted) return;
    setState(() {
      _lastCheckIn = today;
      _streak = nextStreak;
      _checkedInToday = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Điểm danh thành công! Chuỗi hiện tại: $_streak ngày 🔥')));
  }

  Future<void> _showExportDialog() async {
    const formats = <_ExportFormat>[
      _ExportFormat('txt', 'Văn bản thuần', 'TXT', Icons.text_snippet_outlined),
      _ExportFormat('md', 'Markdown', 'MD', Icons.code),
      _ExportFormat('html', 'Trang web', 'HTML', Icons.language),
      _ExportFormat('json', 'Sao lưu đầy đủ dữ liệu', 'JSON', Icons.data_object),
      _ExportFormat('csv', 'Bảng dữ liệu', 'CSV', Icons.table_chart_outlined),
      _ExportFormat('docx', 'Microsoft Word', 'DOCX', Icons.description_outlined),
      _ExportFormat('pdf', 'Tài liệu PDF', 'PDF', Icons.picture_as_pdf_outlined),
    ];
    final selected = await showDialog<_ExportFormat>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171720),
        title: const Text('Chọn định dạng xuất', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView(shrinkWrap: true, children: formats.map((format) => ListTile(
            leading: Icon(format.icon, color: widget.themeColor),
            title: Text(format.label, style: const TextStyle(color: Colors.white)),
            trailing: Text('.${format.extension}', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
            onTap: () => Navigator.pop(dialogContext, format),
          )).toList()),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy'))],
      ),
    );
    if (selected != null) await _exportNotes(selected);
  }

  Future<void> _exportNotes(_ExportFormat format) async {
    if (_notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có bài viết để xuất.')));
      return;
    }
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      String textContent() => _notes.map((note) => '${note.title}\n${List<String>.filled(note.title.length, '=').join()}\n${notePlainText(note.content)}').join('\n\n\n');
      List<int> bytes;
      switch (format.id) {
        case 'txt':
          bytes = utf8.encode(textContent());
          break;
        case 'md':
          bytes = utf8.encode(_notes.map((note) => '# ${note.title}\n\n${_markdownForContent(note.content)}').join('\n\n---\n\n'));
          break;
        case 'html':
          final parts = _notes.map((note) => '<article><h1>${htmlEscape.convert(note.title)}</h1>${_htmlForContent(note.content)}</article>').join('<hr>');
          bytes = utf8.encode('<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Novel App export</title><style>body{font-family:Arial,sans-serif;max-width:850px;margin:40px auto;padding:0 18px;line-height:1.7;color:#222}article{margin-bottom:36px}h1{color:#5b4bce}p{white-space:pre-wrap}</style></head><body>$parts</body></html>');
          break;
        case 'json':
          bytes = utf8.encode(jsonEncode(_notes.map((note) => <String, dynamic>{
            'id': note.id,
            'title': note.title,
            'contentDelta': jsonDecode(_storedContentForJson(note.content)),
            'plainText': notePlainText(note.content),
            'words': countWords(notePlainText(note.content)),
            'isPinned': note.isPinned,
            'updatedAt': note.updatedAt.toIso8601String(),
          }).toList()));
          break;
        case 'csv':
          final rows = <String>['title,content,words,isPinned,updatedAt'];
          for (final note in _notes) {
            rows.add([_csvEscape(note.title), _csvEscape(notePlainText(note.content)), countWords(notePlainText(note.content)).toString(), note.isPinned.toString(), _csvEscape(note.updatedAt.toIso8601String())].join(','));
          }
          bytes = utf8.encode(rows.join('\r\n'));
          break;
        case 'docx':
          bytes = _buildDocxBytes(_notes);
          break;
        case 'pdf':
          bytes = await _buildPdfBytes(_notes);
          break;
        default:
          throw UnsupportedError('Định dạng không hỗ trợ.');
      }
      final file = File('${Directory.systemTemp.path}/novel_export_$stamp.${format.extension.toLowerCase()}');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Xuất từ Novel App - ${_notes.length} bài viết');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không xuất được tệp: $error')));
    }
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.bolt, color: widget.themeColor),
            const SizedBox(width: 8),
            const Text('Azrael Novel App',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            '"app được thiết kế và thực hiện bởi azrael.!!!, hãy trải nghiệm và thả hồn vào từng con chữ"',
            style: TextStyle(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
                height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Trải nghiệm ngay',
                style: TextStyle(color: widget.themeColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoalDialog() async {
    final goal = await showDialog<int>(
      context: context,
      builder: (context) => _GoalDialog(
        initialGoal: _dailyGoal,
        themeColor: widget.themeColor,
      ),
    );
    if (goal == null || !mounted) return;
    setState(() {
      _dailyGoal = goal;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('novel_daily_goal', goal);
  }

  Future<void> _confirmDelete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Xóa bài viết?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '"${note.title}" sẽ bị xóa vĩnh viễn.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
    });
  }

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute<Note>(
        builder: (context) => EditorScreen(
          note: note,
          themeColor: widget.themeColor,
          dailyGoal: _dailyGoal,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      final index = _notes.indexWhere((n) => n.id == result.id);
      if (index >= 0) {
        final addedWords = result.words - _notes[index].words;
        if (addedWords > 0) _addWordsToday(addedWords);
        _notes[index] = result;
      } else {
        _addWordsToday(result.words);
        _notes.add(result);
      }
      _sortNotes();
    });
  }

  void _togglePin(String id) {
    setState(() {
      final index = _notes.indexWhere((n) => n.id == id);
      if (index < 0) return;
      _notes[index] = _notes[index].copyWith(isPinned: !_notes[index].isPinned);
      _sortNotes();
    });
  }

  /// Bài ghim lên trước, sau đó bài sửa gần nhất lên trước.
  /// So sánh theo thứ tự đầy đủ nên kết quả luôn ổn định.
  void _sortNotes() {
    _notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byDate = b.updatedAt.compareTo(a.updatedAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredNotes = _notes.where((n) {
      return n.title.toLowerCase().contains(query) ||
          notePlainText(n.content).toLowerCase().contains(query);
    }).toList();

    final todayWords = _todayWords;
    final ratio = _dailyGoal > 0 ? todayWords / _dailyGoal : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B0D14), Color(0xFF11101A), Color(0xFF08090D)],
                ),
              ),
            ),
          ),
          // Quầng màu loang mượt và nhẹ hơn, tránh mảng màu gắt.
          Positioned(
            top: -150,
            left: -130,
            child: Container(
              width: 430,
              height: 430,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.themeColor.fade(_glowIntensity),
                    widget.themeColor.fade(_glowIntensity * 0.42),
                    widget.themeColor.fade(_glowIntensity * 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.36, 0.68, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            right: -170,
            bottom: -180,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6).fade(_glowIntensity * 0.42),
                    const Color(0xFF6366F1).fade(_glowIntensity * 0.18),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(todayWords, progress),
                  const SizedBox(height: 16),
                  _buildSearchField(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildNotesView(filteredNotes)),
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

  Widget _buildHeader(int todayWords, double progress) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.08),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Giới thiệu',
                icon: Icon(Icons.bolt, color: widget.themeColor, size: 20),
                onPressed: _showAboutDialog,
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Mở menu tùy chỉnh',
                icon: const Icon(Icons.star_outline,
                    color: Colors.amber, size: 20),
                onPressed: _showAppMenu,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _showGoalDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.fade(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('chào mừng đã đến với app',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Hôm nay: $todayWords / $_dailyGoal từ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(widget.themeColor),
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
            color: Colors.white.fade(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: IconButton(
            tooltip: _isGridMode ? 'Xem dạng danh sách' : 'Xem dạng lưới',
            icon: Icon(
              _isGridMode ? Icons.grid_view : Icons.view_agenda,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _isGridMode = !_isGridMode;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (val) => setState(() => _searchQuery = val),
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
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, height: 1.5),
        ),
      );
    }

    // Chừa chỗ phía dưới để nút cộng không che bài viết cuối cùng.
    const listPadding = EdgeInsets.only(bottom: 88);

    if (_isGridMode) {
      return GridView.builder(
        padding: listPadding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 168,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildNoteCard(note, key: ValueKey(note.id));
        },
      );
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return _buildNoteCard(note, key: ValueKey(note.id));
      },
    );
  }

  Widget _buildNoteCard(Note note, {Key? key}) {
    final contentText = Text(
      notePlainText(note.content).isEmpty
          ? '(Chưa có nội dung)'
          : previewText(notePlainText(note.content)),
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
            color:
                note.isPinned ? widget.themeColor.fade(0.5) : Colors.white10,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: note.isPinned ? 'Bỏ ghim' : 'Ghim bài viết',
                  icon: Icon(
                    Icons.push_pin,
                    size: 16,
                    color: note.isPinned ? Colors.amber : Colors.white24,
                  ),
                  onPressed: () => _togglePin(note.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Chế độ lưới có chiều cao cố định nên dùng Expanded;
            // chế độ danh sách có chiều cao tự do nên KHÔNG được dùng Expanded
            // (nếu dùng sẽ bị lỗi "non-zero flex but unbounded height").
            if (_isGridMode) Expanded(child: contentText) else contentText,
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${countWords(notePlainText(note.content))} từ',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(formatDate(note.updatedAt),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= HỘP THOẠI ĐẶT MỤC TIÊU =================
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({
    required this.initialGoal,
    required this.themeColor,
  });

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
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() {
        _error = 'Nhập số từ lớn hơn 0';
      });
      return;
    }
    Navigator.of(context).pop(value);
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
          if (_error != null) {
            setState(() {
              _error = null;
            });
          }
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

// ================= MÀN HÌNH SOẠN THẢO VĂN BẢN (EDITOR) =================
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.note,
    required this.themeColor,
    required this.dailyGoal,
  });

  final Note? note;
  final Color themeColor;
  final int dailyGoal;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleController;
  late final QuillController _quillController;
  late final String _initialDeltaJson;
  int _wordCount = 0;
  bool _restReminderShown = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    final document = documentFromStoredContent(widget.note?.content);
    _quillController = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _initialDeltaJson = jsonEncode(_quillController.document.toDelta().toJson());
    _wordCount = countWords(_quillController.document.toPlainText());
    _quillController.addListener(_onDocumentChanged);
  }

  void _onDocumentChanged() {
    final plainText = _quillController.document.toPlainText();
    final count = countWords(plainText);
    if (count != _wordCount && mounted) {
      setState(() => _wordCount = count);
    }
    // Nhắc một lần khi vượt mục tiêu để tránh hiện thông báo liên tục mỗi ký tự.
    if (count > widget.dailyGoal && !_restReminderShown) {
      _restReminderShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF252535),
            content: const Text('M đã vượt mục tiêu viết. Nghỉ 5 phút, uống nước và thư giãn mắt nhé! ☕'),
            action: SnackBarAction(label: 'Đã hiểu', textColor: widget.themeColor, onPressed: () {}),
          ),
        );
      });
    }
  }

  void _saveAndExit() {
    final title = _titleController.text.trim();
    final plainText = _quillController.document.toPlainText().trimRight();
    final serialized = jsonEncode(_quillController.document.toDelta().toJson());
    final original = widget.note;

    if (title.isEmpty && plainText.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final finalTitle = title.isEmpty ? 'Bài viết mới' : title;
    if (original != null && original.title == finalTitle && serialized == _initialDeltaJson) {
      Navigator.of(context).pop();
      return;
    }

    final now = DateTime.now();
    final saved = Note(
      id: original?.id ?? now.microsecondsSinceEpoch.toString(),
      title: finalTitle,
      content: serialized,
      isPinned: original?.isPinned ?? false,
      words: countWords(plainText),
      updatedAt: now,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  void dispose() {
    _quillController.removeListener(_onDocumentChanged);
    _quillController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0B11),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0E15),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Lưu và quay lại',
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: _saveAndExit,
          ),
          title: const Text('Đang viết', style: TextStyle(color: Colors.white, fontSize: 16)),
          actions: [
            IconButton(
              tooltip: 'Lưu bài viết',
              icon: Icon(Icons.check_circle_outline, color: widget.themeColor, size: 27),
              onPressed: _saveAndExit,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF11131C), const Color(0xFF090A10), const Color(0xFF11101B)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [widget.themeColor.fade(0.13), widget.themeColor.fade(0.04), Colors.transparent]),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      autofocus: widget.note == null,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Tiêu đề chương / bài viết...',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: widget.themeColor.fade(0.16), borderRadius: BorderRadius.circular(12)),
                          child: Text('$_wordCount từ', style: TextStyle(color: widget.themeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _wordCount > widget.dailyGoal ? 'Đã vượt mục tiêu - nhớ nghỉ ngơi' : 'Mục tiêu: ${widget.dailyGoal} từ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _wordCount > widget.dailyGoal ? Colors.orangeAccent : Colors.white38, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF171923).fade(0.88), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: QuillSimpleToolbar(
                          controller: _quillController,
                          configurations: const QuillSimpleToolbarConfigurations(),
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 20),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.fade(0.025), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
                        child: QuillEditor.basic(
                          controller: _quillController,
                          configurations: const QuillEditorConfigurations(
                            placeholder: 'Bắt đầu đặt bút thả hồn vào câu chuyện...',
                            padding: EdgeInsets.all(10),
                            expands: true,
                            autoFocus: false,
                            readOnly: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Thanh công cụ có in đậm, in nghiêng, gạch chân, H1/H2/H3, danh sách, căn lề và hoàn tác/làm lại.', style: TextStyle(color: Colors.white30, fontSize: 10), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportFormat {
  const _ExportFormat(this.id, this.label, this.extension, this.icon);
  final String id;
  final String label;
  final String extension;
  final IconData icon;
}
