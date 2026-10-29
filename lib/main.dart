import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(NovelApp(state: state));
}

// ================= HẰNG SỐ GIAO DIỆN =================

/// Các màu chủ đề (chọn trong menu ngôi sao).
const List<Color> kThemeColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFA855F7),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

class BgOption {
  const BgOption(this.name, this.color);
  final String name;
  final Color color;
}

/// Các màu nền tối (chọn trong menu ngôi sao).
const List<BgOption> kBackgrounds = [
  BgOption('Đen thuần', Color(0xFF08080A)),
  BgOption('Than chì', Color(0xFF121217)),
  BgOption('Xanh đêm', Color(0xFF0A1020)),
  BgOption('Nâu cà phê', Color(0xFF15100D)),
];

const List<String> kFontNames = ['Mặc định', 'Có chân', 'Đơn cách'];
const List<String?> kFontFamilies = [null, 'serif', 'monospace'];

const Color kWhite90 = Color(0xE6FFFFFF);

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
      (unit >= 0x2000 && unit <= 0x200B) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;
}

/// Đếm số từ: mỗi cụm ký tự liền nhau (ngăn cách bởi khoảng trắng/xuống dòng)
/// là một từ. Duyệt một lượt, không tạo danh sách trung gian.
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

String _two(int v) => v.toString().padLeft(2, '0');

String formatDate(DateTime date) => '${_two(date.day)}/${_two(date.month)}';

String formatDateLong(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

int _asInt(Object? v, int def) => v is num ? v.toInt() : def;
double _asDouble(Object? v, double def) => v is num ? v.toDouble() : def;
bool _asBool(Object? v, bool def) => v is bool ? v : def;
String _asString(Object? v, String def) => v is String ? v : def;
int _clampIndex(int v, int length) => v < 0 || v >= length ? 0 : v;

// ================= ĐỊNH DẠNG CHỮ (LƯU THEO TỪNG KÝ TỰ) =================
// Mỗi ký tự có 1 số nguyên kiểu bit:
//   bit 0 = đậm, bit 1 = nghiêng, bit 2 = gạch chân, bit 3 = gạch ngang
//   bit 4-5 = kiểu dòng: 0 thường, 1 = H1, 2 = H2, 3 = H3
const int kBold = 1;
const int kItalic = 2;
const int kUnderline = 4;
const int kStrike = 8;

List<int> fitStyles(List<int>? source, int length) {
  final out = List<int>.from(source ?? const <int>[]);
  if (out.length > length) {
    out.removeRange(length, out.length);
  } else if (out.length < length) {
    out.addAll(List<int>.filled(length - out.length, 0));
  }
  return out;
}

String encodeStyles(List<int> s) {
  if (s.isEmpty) return '';
  final parts = <String>[];
  var run = s[0];
  var n = 0;
  for (final v in s) {
    if (v == run) {
      n++;
    } else {
      parts.add('$n:$run');
      run = v;
      n = 1;
    }
  }
  parts.add('$n:$run');
  return parts.join(',');
}

List<int> decodeStyles(String encoded, int length) {
  final out = <int>[];
  if (encoded.isNotEmpty) {
    for (final part in encoded.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final n = int.tryParse(kv[0]);
      final v = int.tryParse(kv[1]);
      if (n == null || v == null || n < 0 || n > 5000000) continue;
      out.addAll(List<int>.filled(n, v));
    }
  }
  return fitStyles(out, length);
}

// ================= MODEL BÀI VIẾT =================
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.styles = '',
    this.isPinned = false,
    required this.words,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final String styles; // định dạng chữ đã mã hóa
  final bool isPinned;
  final int words;
  final DateTime updatedAt;

  Note copyWith({bool? isPinned}) {
    return Note(
      id: id,
      title: title,
      content: content,
      styles: styles,
      isPinned: isPinned ?? this.isPinned,
      words: words,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'styles': styles,
        'pinned': isPinned,
        'words': words,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> m) {
    final content = _asString(m['content'], '');
    return Note(
      id: _asString(m['id'], DateTime.now().microsecondsSinceEpoch.toString()),
      title: _asString(m['title'], ''),
      content: content,
      styles: _asString(m['styles'], ''),
      isPinned: _asBool(m['pinned'], false),
      words: countWords(content),
      updatedAt: DateTime.tryParse(_asString(m['updatedAt'], '')) ??
          DateTime.now(),
    );
  }
}

List<Note> _sampleNotes() {
  final now = DateTime.now();
  const welcome =
      'Chào mừng bạn đến với ứng dụng Novel App! Nhấn nút cộng ở góc dưới để '
      'tạo bài viết mới hoặc nhấn vào bài này để chỉnh sửa. Nhấn giữ một bài '
      'viết để xóa. Nhấn ngôi sao ở góc trên để mở menu: giao diện, xuất file '
      'và điểm danh chuỗi.';
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

// ================= ĐỊNH DẠNG XUẤT FILE =================
enum ExportFormat { txt, md, html, rtf, docx, json, csv }

extension ExportFormatInfo on ExportFormat {
  String get label => const {
        ExportFormat.txt: 'TXT',
        ExportFormat.md: 'Markdown',
        ExportFormat.html: 'HTML',
        ExportFormat.rtf: 'RTF',
        ExportFormat.docx: 'DOCX',
        ExportFormat.json: 'JSON',
        ExportFormat.csv: 'CSV',
      }[this]!;

  String get ext => const {
        ExportFormat.txt: 'txt',
        ExportFormat.md: 'md',
        ExportFormat.html: 'html',
        ExportFormat.rtf: 'rtf',
        ExportFormat.docx: 'docx',
        ExportFormat.json: 'json',
        ExportFormat.csv: 'csv',
      }[this]!;

  String get mime => const {
        ExportFormat.txt: 'text/plain',
        ExportFormat.md: 'text/markdown',
        ExportFormat.html: 'text/html',
        ExportFormat.rtf: 'application/rtf',
        ExportFormat.docx:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.json: 'application/json',
        ExportFormat.csv: 'text/csv',
      }[this]!;

  bool get isText => this != ExportFormat.docx;
}

// ================= TRẠNG THÁI TOÀN APP (LƯU BỀN) =================
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppState._(prefs);
    s._restore();
    return s;
  }

  // Giao diện
  int themeIndex = 0;
  int bgIndex = 0;
  bool aurora = true;
  double fontSize = 17;
  double lineHeight = 1.6;
  int fontIndex = 0;
  bool isGridMode = true;

  // Mục tiêu viết
  int dailyGoal = 500;
  bool restReminder = true;
  String restShownDay = '';
  int _wordsToday = 0;
  DateTime _goalDay = dateOnly(DateTime.now());

  // Điểm danh
  final Set<String> checkins = <String>{};

  // Xuất file
  ExportFormat exportFormat = ExportFormat.docx;
  bool exportTitle = true;
  bool exportMeta = false;

  List<Note> notes = [];

  Color get themeColor => kThemeColors[themeIndex];
  Color get bgColor => kBackgrounds[bgIndex].color;
  String? get fontFamily => kFontFamilies[fontIndex];

  // ---- đọc / ghi ----
  void _restore() {
    try {
      final raw = _prefs.getString('settings');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        themeIndex = _clampIndex(_asInt(m['themeIndex'], 0), kThemeColors.length);
        bgIndex = _clampIndex(_asInt(m['bgIndex'], 0), kBackgrounds.length);
        aurora = _asBool(m['aurora'], true);
        fontSize = _asDouble(m['fontSize'], 17).clamp(14.0, 26.0).toDouble();
        lineHeight = _asDouble(m['lineHeight'], 1.6).clamp(1.2, 2.4).toDouble();
        fontIndex = _clampIndex(_asInt(m['fontIndex'], 0), kFontFamilies.length);
        isGridMode = _asBool(m['grid'], true);
        dailyGoal = math.max(1, _asInt(m['dailyGoal'], 500));
        restReminder = _asBool(m['restReminder'], true);
        restShownDay = _asString(m['restShownDay'], '');
        _wordsToday = math.max(0, _asInt(m['wordsToday'], 0));
        _goalDay = DateTime.tryParse(_asString(m['goalDay'], '')) ??
            dateOnly(DateTime.now());
        _goalDay = dateOnly(_goalDay);
        exportFormat = ExportFormat
            .values[_clampIndex(_asInt(m['exportFormat'], 4), ExportFormat.values.length)];
        exportTitle = _asBool(m['exportTitle'], true);
        exportMeta = _asBool(m['exportMeta'], false);
        final list = m['checkins'];
        if (list is List) {
          for (final e in list) {
            if (e is String) checkins.add(e);
          }
        }
      }
    } catch (_) {
      // Dữ liệu cài đặt hỏng: dùng mặc định.
    }
    try {
      final rawNotes = _prefs.getString('notes');
      if (rawNotes == null) {
        notes = _sampleNotes();
      } else {
        final list = jsonDecode(rawNotes) as List<dynamic>;
        notes = list
            .whereType<Map<String, dynamic>>()
            .map(Note.fromJson)
            .toList();
      }
    } catch (_) {
      notes = _sampleNotes();
    }
    _sortNotes();
  }

  void _saveSettings() {
    _prefs.setString(
      'settings',
      jsonEncode({
        'themeIndex': themeIndex,
        'bgIndex': bgIndex,
        'aurora': aurora,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontIndex': fontIndex,
        'grid': isGridMode,
        'dailyGoal': dailyGoal,
        'restReminder': restReminder,
        'restShownDay': restShownDay,
        'wordsToday': _wordsToday,
        'goalDay': dateKey(_goalDay),
        'exportFormat': exportFormat.index,
        'exportTitle': exportTitle,
        'exportMeta': exportMeta,
        'checkins': checkins.toList(),
      }),
    );
  }

  void _saveNotes() {
    _prefs.setString(
      'notes',
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }

  /// Đổi một cài đặt, lưu và cập nhật giao diện.
  void change(VoidCallback fn) {
    fn();
    _saveSettings();
    notifyListeners();
  }

  // ---- số từ hôm nay ----
  int get todayWords =>
      dateOnly(DateTime.now()) == _goalDay ? _wordsToday : 0;

  void _addWordsToday(int delta) {
    final today = dateOnly(DateTime.now());
    if (today != _goalDay) {
      _goalDay = today;
      _wordsToday = 0;
    }
    _wordsToday = math.max(0, _wordsToday + delta);
  }

  bool get restShownToday => restShownDay == dateKey(DateTime.now());

  void markRestShown() {
    restShownDay = dateKey(DateTime.now());
    _saveSettings();
  }

  // ---- điểm danh chuỗi ----
  bool hasCheckin(DateTime d) => checkins.contains(dateKey(d));

  bool get checkedInToday => hasCheckin(DateTime.now());

  void checkInToday() => change(() => checkins.add(dateKey(DateTime.now())));

  int get streak {
    var d = dateOnly(DateTime.now());
    if (!hasCheckin(d)) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (hasCheckin(d)) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  int get longestStreak {
    final days = checkins
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map(dateOnly)
        .toList()
      ..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  // ---- bài viết ----
  void _sortNotes() {
    notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byDate = b.updatedAt.compareTo(a.updatedAt);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
  }

  void saveNote(Note n) {
    final i = notes.indexWhere((x) => x.id == n.id);
    if (i >= 0) {
      _addWordsToday(n.words - notes[i].words);
      notes[i] = n;
    } else {
      _addWordsToday(n.words);
      notes.add(n);
    }
    _sortNotes();
    _saveNotes();
    _saveSettings();
    notifyListeners();
  }

  void deleteNote(String id) {
    notes.removeWhere((n) => n.id == id);
    _saveNotes();
    notifyListeners();
  }

  void togglePin(String id) {
    final i = notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    notes[i] = notes[i].copyWith(isPinned: !notes[i].isPinned);
    _sortNotes();
    _saveNotes();
    notifyListeners();
  }
}

// ================= Ô SOẠN THẢO CÓ ĐỊNH DẠNG =================
class _Snap {
  _Snap(this.text, this.styles, this.selection);
  final String text;
  final List<int> styles;
  final TextSelection selection;
}

class RichTextController extends TextEditingController {
  RichTextController({String text = '', List<int>? styles})
      : _styles = fitStyles(styles, text.length),
        super(text: text);

  List<int> _styles;
  int typingInline = 0;
  int typingBlock = 0;

  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  DateTime _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  String encodedStyles() {
    if (_styles.length != text.length) {
      _styles = fitStyles(_styles, text.length);
    }
    return encodeStyles(_styles);
  }

  /// Lấy phần định dạng ứng với đoạn [start, end) của văn bản.
  String encodedStylesRange(int start, int end) {
    if (_styles.length != text.length) {
      _styles = fitStyles(_styles, text.length);
    }
    return encodeStyles(_styles.sublist(start, end));
  }

  // ---- Lịch sử hoàn tác ----
  void _recordUndo({bool force = false}) {
    final now = DateTime.now();
    final gap = now.difference(_lastEdit);
    _lastEdit = now;
    if (!force && _undo.isNotEmpty && gap.inMilliseconds < 800) {
      _redo.clear();
      return;
    }
    _undo.add(_Snap(text, List<int>.from(_styles), selection));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snap s) {
    _styles = List<int>.from(s.styles);
    final sel = s.selection.isValid
        ? TextSelection(
            baseOffset: math.min(s.selection.baseOffset, s.text.length),
            extentOffset: math.min(s.selection.extentOffset, s.text.length),
          )
        : TextSelection.collapsed(offset: s.text.length);
    _syncTyping(s.text, sel);
    super.value = TextEditingValue(text: s.text, selection: sel);
    _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snap(text, List<int>.from(_styles), selection));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snap(text, List<int>.from(_styles), selection));
    _restore(_redo.removeLast());
  }

  // ---- Theo dõi thay đổi chữ để giữ định dạng khớp từng ký tự ----
  @override
  set value(TextEditingValue newValue) {
    final old = value;
    var next = newValue;
    if (next.text != old.text) {
      next = _autoContinueList(old, next);
      _recordUndo();
      _applyDiff(old.text, next.text);
      super.value = next;
      return;
    }
    final moved = next.selection.baseOffset != old.selection.baseOffset ||
        next.selection.extentOffset != old.selection.extentOffset;
    if (moved) _syncTyping(next.text, next.selection);
    super.value = next;
  }

  void _applyDiff(String old, String neu) {
    if (_styles.length != old.length) {
      _styles = fitStyles(_styles, old.length);
    }
    final minLen = math.min(old.length, neu.length);
    var p = 0;
    while (p < minLen && old.codeUnitAt(p) == neu.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p &&
        old.codeUnitAt(old.length - 1 - s) ==
            neu.codeUnitAt(neu.length - 1 - s)) {
      s++;
    }
    final removeEnd = old.length - s;
    final insertEnd = neu.length - s;

    var block = typingBlock;
    if (p > 0 && old.codeUnitAt(p - 1) != 10) {
      block = (_styles[p - 1] >> 4) & 3;
    } else if (p < old.length && old.codeUnitAt(p) != 10) {
      block = (_styles[p] >> 4) & 3;
    }

    final inserted = neu.substring(p, insertEnd);
    final added = <int>[];
    for (var i = 0; i < inserted.length; i++) {
      added.add(typingInline | (block << 4));
      if (inserted.codeUnitAt(i) == 10) block = 0; // sau Enter: dòng thường
    }
    typingBlock = block;
    _styles.replaceRange(p, removeEnd, added);
    if (_styles.length != neu.length) {
      _styles = fitStyles(_styles, neu.length);
    }
  }

  /// Nhấn Enter trên dòng bắt đầu bằng "• " thì tự thêm gạch đầu dòng mới;
  /// nhấn Enter trên dòng chỉ có "• " thì bỏ gạch đầu dòng.
  TextEditingValue _autoContinueList(TextEditingValue old, TextEditingValue next) {
    final t = next.text;
    final cursor = next.selection.baseOffset;
    if (!next.selection.isCollapsed ||
        t.length != old.text.length + 1 ||
        cursor < 1 ||
        cursor > t.length ||
        t.codeUnitAt(cursor - 1) != 10) {
      return next;
    }
    if (old.text != t.substring(0, cursor - 1) + t.substring(cursor)) {
      return next;
    }
    final lineStart = cursor - 1 == 0 ? 0 : t.lastIndexOf('\n', cursor - 2) + 1;
    final line = t.substring(lineStart, cursor - 1);
    if (line == '• ') {
      return next.copyWith(
        text: t.substring(0, lineStart) + t.substring(cursor),
        selection: TextSelection.collapsed(offset: lineStart),
        composing: TextRange.empty,
      );
    }
    if (line.startsWith('• ')) {
      return next.copyWith(
        text: '${t.substring(0, cursor)}• ${t.substring(cursor)}',
        selection: TextSelection.collapsed(offset: cursor + 2),
        composing: TextRange.empty,
      );
    }
    return next;
  }

  void _syncTyping(String t, TextSelection sel) {
    if (!sel.isValid || !sel.isCollapsed) return;
    if (_styles.length != t.length) _styles = fitStyles(_styles, t.length);
    final pos = math.max(0, math.min(sel.baseOffset, t.length));
    if (pos > 0 && t.codeUnitAt(pos - 1) != 10) {
      final s = _styles[pos - 1];
      typingInline = s & 15;
      typingBlock = (s >> 4) & 3;
    } else if (pos < t.length && t.codeUnitAt(pos) != 10) {
      final s = _styles[pos];
      typingInline = s & 15;
      typingBlock = (s >> 4) & 3;
    } else {
      typingInline = 0;
      typingBlock = 0;
    }
  }

  // ---- Trạng thái nút trên thanh công cụ ----
  bool isInlineActive(int bit) {
    final t = text;
    final sel = selection;
    if (sel.isValid && !sel.isCollapsed && _styles.length == t.length) {
      var any = false;
      for (var i = sel.start; i < sel.end; i++) {
        if (t.codeUnitAt(i) == 10) continue;
        any = true;
        if ((_styles[i] & bit) == 0) return false;
      }
      return any;
    }
    return (typingInline & bit) != 0;
  }

  int get activeBlock {
    final t = text;
    final sel = selection;
    if (!sel.isValid || _styles.length != t.length) return typingBlock;
    final pos = math.min(sel.start, t.length);
    if (pos > 0 && t.codeUnitAt(pos - 1) != 10) {
      return (_styles[pos - 1] >> 4) & 3;
    }
    if (pos < t.length && t.codeUnitAt(pos) != 10) {
      return (_styles[pos] >> 4) & 3;
    }
    return typingBlock;
  }

  // ---- Thao tác định dạng ----
  void toggleInline(int bit) {
    final t = text;
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed || _styles.length != t.length) {
      typingInline ^= bit;
      notifyListeners();
      return;
    }
    final makeOn = !isInlineActive(bit);
    _recordUndo(force: true);
    for (var i = sel.start; i < sel.end; i++) {
      if (t.codeUnitAt(i) == 10) continue;
      _styles[i] = makeOn ? (_styles[i] | bit) : (_styles[i] & ~bit);
    }
    notifyListeners();
  }

  (int, int) _lineRange() {
    final t = text;
    final sel = selection;
    final a = sel.isValid ? math.min(sel.start, t.length) : t.length;
    final b = sel.isValid ? math.min(sel.end, t.length) : t.length;
    final ls = a == 0 ? 0 : t.lastIndexOf('\n', a - 1) + 1;
    final endRef = b > a ? b - 1 : b;
    var le = t.indexOf('\n', endRef);
    if (le == -1) le = t.length;
    return (ls, le);
  }

  void setBlock(int target) {
    if (_styles.length != text.length) {
      _styles = fitStyles(_styles, text.length);
    }
    final applied = activeBlock == target ? 0 : target;
    _recordUndo(force: true);
    final (ls, le) = _lineRange();
    for (var i = ls; i < le; i++) {
      _styles[i] = (_styles[i] & 15) | (applied << 4);
    }
    typingBlock = applied;
    notifyListeners();
  }

  void toggleBullet() {
    final t = text;
    final sel = selection;
    final pos = sel.isValid ? math.min(sel.start, t.length) : t.length;
    final ls = pos == 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    final has = t.startsWith('• ', ls);
    final newText = has ? t.replaceRange(ls, ls + 2, '') : t.replaceRange(ls, ls, '• ');
    final newPos = has ? math.max(ls, pos - 2) : pos + 2;
    final keepInline = typingInline;
    typingInline = 0;
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPos),
    );
    typingInline = keepInline;
    notifyListeners();
  }

  void clearFormatting() {
    final t = text;
    final sel = selection;
    if (_styles.length != t.length) _styles = fitStyles(_styles, t.length);
    _recordUndo(force: true);
    if (sel.isValid && !sel.isCollapsed) {
      for (var i = sel.start; i < sel.end; i++) {
        _styles[i] = _styles[i] & ~15;
      }
    }
    final (ls, le) = _lineRange();
    for (var i = ls; i < le; i++) {
      _styles[i] = _styles[i] & 15;
    }
    typingInline = 0;
    typingBlock = 0;
    notifyListeners();
  }

  // ---- Vẽ chữ theo định dạng ----
  TextStyle _styleFor(int key, TextStyle base) {
    final size = base.fontSize ?? 16;
    var s = base;
    final block = (key >> 4) & 3;
    if (block == 1) {
      s = s.copyWith(fontSize: size * 1.75, fontWeight: FontWeight.w800, height: 1.3);
    } else if (block == 2) {
      s = s.copyWith(fontSize: size * 1.4, fontWeight: FontWeight.w700, height: 1.35);
    } else if (block == 3) {
      s = s.copyWith(fontSize: size * 1.15, fontWeight: FontWeight.w700, height: 1.4);
    }
    if ((key & kBold) != 0) s = s.copyWith(fontWeight: FontWeight.w800);
    if ((key & kItalic) != 0) s = s.copyWith(fontStyle: FontStyle.italic);
    final decorations = <TextDecoration>[];
    if ((key & kUnderline) != 0 || (key & 256) != 0) {
      decorations.add(TextDecoration.underline);
    }
    if ((key & kStrike) != 0) decorations.add(TextDecoration.lineThrough);
    if (decorations.isNotEmpty) {
      s = s.copyWith(decoration: TextDecoration.combine(decorations));
    }
    return s;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final t = text;
    if (t.isEmpty) return TextSpan(style: base, text: '');
    if (_styles.length != t.length) _styles = fitStyles(_styles, t.length);
    final comp = value.composing;
    final hasComp = withComposing && value.isComposingRangeValid && !comp.isCollapsed;
    int keyAt(int i) =>
        _styles[i] | ((hasComp && i >= comp.start && i < comp.end) ? 256 : 0);

    final spans = <InlineSpan>[];
    var start = 0;
    while (start < t.length) {
      final k = keyAt(start);
      var end = start + 1;
      while (end < t.length && keyAt(end) == k) {
        end++;
      }
      spans.add(TextSpan(text: t.substring(start, end), style: _styleFor(k, base)));
      start = end;
    }
    return TextSpan(style: base, children: spans);
  }
}

// ================= NỀN LOANG MỀM =================
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({
    super.key,
    required this.color,
    required this.base,
    required this.enabled,
    this.intensity = 1.0,
  });

  final Color color;
  final Color base;
  final bool enabled;
  final double intensity;

  /// Gradient mờ dần theo đường cong mượt (smoothstep), không có viền cứng.
  static RadialGradient _soft(Color c, double alpha, Alignment center, double radius) {
    const steps = 14;
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final k = t * t * (3 - 2 * t);
      colors.add(c.fade(alpha * (1 - k)));
      stops.add(t);
    }
    return RadialGradient(center: center, radius: radius, colors: colors, stops: stops);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: base)),
        if (enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: const Duration(milliseconds: 500),
                builder: (context, c, _) {
                  final main = c ?? color;
                  final hsl = HSLColor.fromColor(main);
                  final second = hsl
                      .withHue((hsl.hue + 45) % 360)
                      .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
                      .toColor();
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _soft(main, 0.30 * intensity,
                                const Alignment(-0.95, -1.0), 1.25),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _soft(second, 0.16 * intensity,
                                const Alignment(1.0, 0.95), 1.1),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ================= XUẤT FILE =================
class _Run {
  const _Run(this.text, this.style);
  final String text;
  final int style;
}

class _Line {
  const _Line(this.block, this.runs);
  final int block;
  final List<_Run> runs;
  bool get isEmpty => runs.isEmpty;
  String get plain => runs.map((r) => r.text).join();
}

List<_Line> _parseLines(Note n) {
  final text = n.content;
  final styles = decodeStyles(n.styles, text.length);
  final lines = <_Line>[];
  var start = 0;
  while (true) {
    final nl = text.indexOf('\n', start);
    final end = nl == -1 ? text.length : nl;
    var block = 0;
    final runs = <_Run>[];
    var i = start;
    while (i < end) {
      if (i == start) block = (styles[i] >> 4) & 3;
      final inl = styles[i] & 15;
      var j = i + 1;
      while (j < end && (styles[j] & 15) == inl) {
        j++;
      }
      runs.add(_Run(text.substring(i, j), inl));
      i = j;
    }
    lines.add(_Line(block, runs));
    if (nl == -1) break;
    start = nl + 1;
  }
  return lines;
}

String _metaOf(Note n) => '${formatDateLong(n.updatedAt)} · ${n.words} từ';

String _escHtml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _escXml(String s) => _escHtml(s).replaceAll('"', '&quot;');

String _mdWrap(String text, int style) {
  if (text.trim().isEmpty || (style & 15) == 0) return text;
  final lead = text.substring(0, text.length - text.trimLeft().length);
  final trail = text.substring(text.trimRight().length);
  var core = text.trim();
  if ((style & kStrike) != 0) core = '~~$core~~';
  if ((style & kUnderline) != 0) core = '<u>$core</u>';
  if ((style & kBold) != 0 && (style & kItalic) != 0) {
    core = '***$core***';
  } else if ((style & kBold) != 0) {
    core = '**$core**';
  } else if ((style & kItalic) != 0) {
    core = '*$core*';
  }
  return '$lead$core$trail';
}

String exportText(ExportFormat f, List<Note> notes, bool withTitle, bool withMeta) {
  switch (f) {
    case ExportFormat.txt:
      return _toTxt(notes, withTitle, withMeta);
    case ExportFormat.md:
      return _toMd(notes, withTitle, withMeta);
    case ExportFormat.html:
      return _toHtml(notes, withTitle, withMeta);
    case ExportFormat.rtf:
      return _toRtf(notes, withTitle, withMeta);
    case ExportFormat.json:
      return const JsonEncoder.withIndent('  ').convert({
        'app': 'Novel App',
        'exportedAt': DateTime.now().toIso8601String(),
        'notes': [
          for (final n in notes)
            {
              'title': n.title,
              'content': n.content,
              'words': n.words,
              'updatedAt': n.updatedAt.toIso8601String(),
              'pinned': n.isPinned,
            }
        ],
      });
    case ExportFormat.csv:
      return _toCsv(notes);
    case ExportFormat.docx:
      return '';
  }
}

String _toTxt(List<Note> notes, bool withTitle, bool withMeta) {
  final parts = <String>[];
  for (final n in notes) {
    final b = StringBuffer();
    if (withTitle) b.writeln(n.title);
    if (withMeta) b.writeln(_metaOf(n));
    if (withTitle || withMeta) b.writeln();
    b.write(n.content);
    parts.add(b.toString());
  }
  return parts.join('\n\n--------------------\n\n');
}

String _toMd(List<Note> notes, bool withTitle, bool withMeta) {
  final parts = <String>[];
  for (final n in notes) {
    final b = StringBuffer();
    if (withTitle) b.writeln('# ${n.title}\n');
    if (withMeta) b.writeln('_${_metaOf(n)}_\n');
    final lines = _parseLines(n).where((l) => !l.isEmpty).toList();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      var body = l.runs.map((r) => _mdWrap(r.text, r.style)).join();
      var prefix = '';
      if (l.block == 1) prefix = '## ';
      if (l.block == 2) prefix = '### ';
      if (l.block == 3) prefix = '#### ';
      final isBullet = l.plain.startsWith('• ');
      if (isBullet) {
        body = body.replaceFirst('• ', '- ');
      }
      b.write('$prefix$body');
      final nextBullet = i + 1 < lines.length && lines[i + 1].plain.startsWith('• ');
      b.write(isBullet && nextBullet ? '\n' : '\n\n');
    }
    parts.add(b.toString().trimRight());
  }
  return parts.join('\n\n---\n\n');
}

String _toHtml(List<Note> notes, bool withTitle, bool withMeta) {
  final b = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="vi"><head><meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>Novel App</title>')
    ..writeln('<style>body{font-family:Georgia,serif;max-width:720px;margin:2em auto;padding:0 1em;line-height:1.7;color:#222}'
        'h1,h2,h3,h4{line-height:1.3}.meta{color:#888;font-size:.85em}article{margin-bottom:3em}</style>')
    ..writeln('</head><body>');
  for (final n in notes) {
    b.writeln('<article>');
    if (withTitle) b.writeln('<h1>${_escHtml(n.title)}</h1>');
    if (withMeta) b.writeln('<p class="meta">${_escHtml(_metaOf(n))}</p>');
    for (final l in _parseLines(n)) {
      if (l.isEmpty) {
        b.writeln('<p>&nbsp;</p>');
        continue;
      }
      final inner = StringBuffer();
      for (final r in l.runs) {
        var s = _escHtml(r.text);
        if ((r.style & kStrike) != 0) s = '<s>$s</s>';
        if ((r.style & kUnderline) != 0) s = '<u>$s</u>';
        if ((r.style & kItalic) != 0) s = '<em>$s</em>';
        if ((r.style & kBold) != 0) s = '<strong>$s</strong>';
        inner.write(s);
      }
      final tag = const {1: 'h2', 2: 'h3', 3: 'h4'}[l.block] ?? 'p';
      b.writeln('<$tag>$inner</$tag>');
    }
    b.writeln('</article>');
  }
  b.writeln('</body></html>');
  return b.toString();
}

String _rtfEsc(String t) {
  final b = StringBuffer();
  for (final u in t.codeUnits) {
    if (u == 0x5C) {
      b.write('\\\\');
    } else if (u == 0x7B) {
      b.write('\\{');
    } else if (u == 0x7D) {
      b.write('\\}');
    } else if (u < 128) {
      b.writeCharCode(u);
    } else {
      final v = u > 32767 ? u - 65536 : u;
      b.write('\\u$v?');
    }
  }
  return b.toString();
}

String _toRtf(List<Note> notes, bool withTitle, bool withMeta) {
  final b = StringBuffer(r'{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Calibri;}}\uc1 ');
  for (var k = 0; k < notes.length; k++) {
    final n = notes[k];
    if (k > 0) b.write(r'\page ');
    if (withTitle) b.write('{\\pard\\sa160\\fs44\\b ${_rtfEsc(n.title)}\\b0\\par}');
    if (withMeta) b.write('{\\pard\\sa160\\fs20\\i ${_rtfEsc(_metaOf(n))}\\i0\\par}');
    for (final l in _parseLines(n)) {
      final size = const {1: 36, 2: 30, 3: 26}[l.block] ?? 24;
      b.write('{\\pard\\sa120\\fs$size ');
      if (l.block != 0) b.write(r'\b ');
      for (final r in l.runs) {
        final open = StringBuffer('{');
        if ((r.style & kBold) != 0) open.write(r'\b ');
        if ((r.style & kItalic) != 0) open.write(r'\i ');
        if ((r.style & kUnderline) != 0) open.write(r'\ul ');
        if ((r.style & kStrike) != 0) open.write(r'\strike ');
        if (open.length == 1) {
          b.write(_rtfEsc(r.text));
        } else {
          b.write('$open${_rtfEsc(r.text)}}');
        }
      }
      b.write(r'\par}');
    }
  }
  b.write('}');
  return b.toString();
}

String _toCsv(List<Note> notes) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('Tiêu đề,Số từ,Cập nhật,Nội dung\r\n');
  for (final n in notes) {
    b.write('${q(n.title)},${n.words},${q(formatDateLong(n.updatedAt))},${q(n.content)}\r\n');
  }
  return b.toString();
}

// ---- DOCX (tự đóng gói, không cần thư viện ngoài) ----
String _docxRun(String text, int style, int size, {bool bold = false}) {
  final b = StringBuffer('<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>');
  if (bold || (style & kBold) != 0) b.write('<w:b/>');
  if ((style & kItalic) != 0) b.write('<w:i/>');
  if ((style & kStrike) != 0) b.write('<w:strike/>');
  b.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
  if ((style & kUnderline) != 0) b.write('<w:u w:val="single"/>');
  b.write('</w:rPr><w:t xml:space="preserve">${_escXml(text)}</w:t></w:r>');
  return b.toString();
}

Uint8List exportDocx(List<Note> notes, bool withTitle, bool withMeta) {
  final body = StringBuffer();
  for (var k = 0; k < notes.length; k++) {
    final n = notes[k];
    if (k > 0) body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    if (withTitle) {
      body.write('<w:p><w:pPr><w:spacing w:after="160"/><w:outlineLvl w:val="0"/></w:pPr>'
          '${_docxRun(n.title, 0, 44, bold: true)}</w:p>');
    }
    if (withMeta) {
      body.write('<w:p><w:pPr><w:spacing w:after="160"/></w:pPr>'
          '${_docxRun(_metaOf(n), kItalic, 20)}</w:p>');
    }
    for (final l in _parseLines(n)) {
      final size = const {1: 36, 2: 30, 3: 26}[l.block] ?? 24;
      final outline = l.block == 0 ? '' : '<w:outlineLvl w:val="${l.block}"/>';
      body.write('<w:p><w:pPr><w:spacing w:after="120"/>$outline</w:pPr>');
      for (final r in l.runs) {
        body.write(_docxRun(r.text, r.style, size, bold: l.block != 0));
      }
      body.write('</w:p>');
    }
  }
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode('$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>'),
    '_rels/.rels': utf8.encode('$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>'),
    'word/document.xml': utf8.encode('$head<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>'),
  };
  return _zipStored(files);
}

List<int> _u16(int v) => [v & 255, (v >> 8) & 255];
List<int> _u32(int v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255];

final List<int> _crcTable = () {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 255] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Đóng gói ZIP không nén (đủ để Word/Google Docs mở được file .docx).
Uint8List _zipStored(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  files.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final crc = _crc32(data);
    final offset = out.length;
    out
      ..add(_u32(0x04034B50))
      ..add(_u16(20))
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0x21))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0))
      ..add(nameBytes)
      ..add(data);
    central
      ..add(_u32(0x02014B50))
      ..add(_u16(20))
      ..add(_u16(20))
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0x21))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(offset))
      ..add(nameBytes);
    count++;
  });
  final centralBytes = central.toBytes();
  final centralOffset = out.length;
  out
    ..add(centralBytes)
    ..add(_u32(0x06054B50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(count))
    ..add(_u16(count))
    ..add(_u32(centralBytes.length))
    ..add(_u32(centralOffset))
    ..add(_u16(0));
  return out.toBytes();
}

String _safeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
  if (cleaned.isEmpty) return 'novel_app';
  return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
}

Future<void> shareExport(AppState s, List<Note> notes) async {
  final f = s.exportFormat;
  final List<int> bytes;
  if (f == ExportFormat.docx) {
    bytes = exportDocx(notes, s.exportTitle, s.exportMeta);
  } else {
    final text = exportText(f, notes, s.exportTitle, s.exportMeta);
    bytes = [if (f == ExportFormat.csv) ...[0xEF, 0xBB, 0xBF], ...utf8.encode(text)];
  }
  final base = notes.length == 1
      ? _safeFileName(notes.first.title)
      : 'novel_app_${dateKey(DateTime.now())}';
  final dir = await Directory.systemTemp.createTemp('novel_export');
  final file = File('${dir.path}/$base.${f.ext}');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: f.mime)],
    subject: '$base.${f.ext}',
  );
}

// ================= GỐC ỨNG DỤNG =================
class NovelApp extends StatelessWidget {
  const NovelApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final color = state.themeColor;
        return MaterialApp(
          title: 'Novel App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: state.bgColor,
            primaryColor: color,
            colorScheme: ColorScheme.dark(primary: color),
          ),
          home: HomeScreen(state: state),
        );
      },
    );
  }
}

// ================= MÀN HÌNH CHÍNH =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';

  AppState get s => widget.state;

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.bolt, color: s.themeColor),
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
                color: Colors.white70, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Trải nghiệm ngay', style: TextStyle(color: s.themeColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoalDialog() async {
    final result = await showDialog<_GoalResult>(
      context: context,
      builder: (context) => _GoalDialog(
        initialGoal: s.dailyGoal,
        initialRemind: s.restReminder,
        themeColor: s.themeColor,
      ),
    );
    if (result == null || !mounted) return;
    s.change(() {
      s.dailyGoal = result.goal;
      s.restReminder = result.remind;
    });
  }

  Future<void> _confirmDelete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Xóa bài viết?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('"${note.title}" sẽ bị xóa vĩnh viễn.',
            style: const TextStyle(color: Colors.white70)),
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
    s.deleteNote(note.id);
  }

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute<Note>(
        builder: (context) => EditorScreen(note: note, state: s),
      ),
    );
    if (result == null || !mounted) return;
    s.saveNote(result);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredNotes = s.notes.where((n) {
      return n.title.toLowerCase().contains(query) ||
          n.content.toLowerCase().contains(query);
    }).toList();

    final todayWords = s.todayWords;
    final ratio = s.dailyGoal > 0 ? todayWords / s.dailyGoal : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          AuroraBackground(
            color: s.themeColor,
            base: s.bgColor,
            enabled: s.aurora,
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
        backgroundColor: s.themeColor,
        tooltip: 'Viết bài mới',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildHeader(int todayWords, double progress) {
    final over = todayWords > s.dailyGoal;
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
                icon: Icon(Icons.bolt, color: s.themeColor, size: 20),
                onPressed: _showAboutDialog,
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Menu: giao diện, xuất file, điểm danh',
                icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                onPressed: () => showAppMenu(context, s),
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
                  Text(
                    'Hôm nay: $todayWords / ${s.dailyGoal} từ${over ? ' · vượt mục tiêu' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: over ? Colors.amber : Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        over ? Colors.amber : s.themeColor),
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
            tooltip: s.isGridMode ? 'Xem dạng danh sách' : 'Xem dạng lưới',
            icon: Icon(s.isGridMode ? Icons.grid_view : Icons.view_agenda, size: 18),
            onPressed: () => s.change(() => s.isGridMode = !s.isGridMode),
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
      final message = s.notes.isEmpty
          ? 'Chưa có bài viết nào.\nNhấn nút cộng để bắt đầu viết.'
          : 'Không tìm thấy bài viết phù hợp.';
      return Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, height: 1.5)),
      );
    }

    const listPadding = EdgeInsets.only(bottom: 88);

    if (s.isGridMode) {
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
    final grid = s.isGridMode;
    final contentText = Text(
      note.content.isEmpty ? '(Chưa có nội dung)' : previewText(note.content),
      maxLines: grid ? 3 : 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white60, fontSize: 13),
    );

    return GestureDetector(
      key: key,
      onTap: () => _openEditor(note),
      onLongPress: () => _confirmDelete(note),
      child: Container(
        margin: EdgeInsets.only(bottom: grid ? 0 : 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.fade(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: note.isPinned ? s.themeColor.fade(0.5) : Colors.white10,
          ),
        ),
        child: Column(
          mainAxisSize: grid ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Không có tiêu đề' : note.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: note.isPinned ? 'Bỏ ghim' : 'Ghim bài viết',
                  icon: Icon(Icons.push_pin,
                      size: 16,
                      color: note.isPinned ? Colors.amber : Colors.white24),
                  onPressed: () => s.togglePin(note.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (grid) Expanded(child: contentText) else contentText,
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

// ================= MENU NGÔI SAO =================
Future<void> showAppMenu(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scroll) => _MenuSheet(state: state, scroll: scroll),
    ),
  );
}

class _MenuSheet extends StatelessWidget {
  const _MenuSheet({required this.state, required this.scroll});

  final AppState state;
  final ScrollController scroll;

  Widget _title(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF14141A),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final color = state.themeColor;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.star_rounded, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('Menu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              _title('Điểm danh chuỗi', Icons.local_fire_department_rounded, Colors.orange),
              _StreakCard(state: state),
              _title('Mục tiêu viết', Icons.flag_rounded, color),
              _GoalTile(state: state),
              _title('Giao diện', Icons.palette_rounded, color),
              _AppearanceSection(state: state),
              _title('Xuất file', Icons.ios_share_rounded, color),
              ExportPanel(
                state: state,
                notesBuilder: () => List<Note>.from(state.notes),
                heading: 'Xuất tất cả ${state.notes.length} bài viết',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = state.themeColor;
    final today = dateOnly(DateTime.now());
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.fade(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: Colors.orange, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${state.streak} ngày liên tiếp',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      'Kỷ lục ${state.longestStreak} ngày · Tổng ${state.checkins.length} lần điểm danh',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in days)
                Column(
                  children: [
                    Text(labels[d.weekday - 1],
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.hasCheckin(d) ? color : Colors.white.fade(0.06),
                        border: d == today
                            ? Border.all(color: Colors.white70, width: 1.5)
                            : null,
                      ),
                      child: state.hasCheckin(d)
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.fade(0.08),
                disabledForegroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: state.checkedInToday ? null : state.checkInToday,
              icon: Icon(state.checkedInToday ? Icons.check_circle : Icons.touch_app),
              label: Text(state.checkedInToday
                  ? 'Đã điểm danh hôm nay'
                  : 'Điểm danh hôm nay'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = state.themeColor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.fade(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text('Mục tiêu hằng ngày: ${state.dailyGoal} từ'),
            subtitle: Text('Hôm nay đã viết ${state.todayWords} từ',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.edit, size: 18, color: Colors.white54),
            onTap: () async {
              final r = await showDialog<_GoalResult>(
                context: context,
                builder: (_) => _GoalDialog(
                  initialGoal: state.dailyGoal,
                  initialRemind: state.restReminder,
                  themeColor: color,
                ),
              );
              if (r == null) return;
              state.change(() {
                state.dailyGoal = r.goal;
                state.restReminder = r.remind;
              });
            },
          ),
          SwitchListTile(
            activeColor: color,
            title: const Text('Nhắc nghỉ ngơi khi viết quá mục tiêu'),
            value: state.restReminder,
            onChanged: (v) => state.change(() => state.restReminder = v),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.state});

  final AppState state;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final color = state.themeColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.fade(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Màu chủ đề'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < kThemeColors.length; i++)
                GestureDetector(
                  onTap: () => state.change(() => state.themeIndex = i),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kThemeColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: state.themeIndex == i ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: state.themeIndex == i
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          _label('Màu nền'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < kBackgrounds.length; i++)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(kBackgrounds[i].name),
                  avatar: CircleAvatar(
                    backgroundColor: kBackgrounds[i].color,
                    radius: 8,
                  ),
                  selected: state.bgIndex == i,
                  selectedColor: color.fade(0.35),
                  backgroundColor: Colors.white.fade(0.06),
                  side: const BorderSide(color: Colors.white12),
                  onSelected: (_) => state.change(() => state.bgIndex = i),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: color,
            title: const Text('Hiệu ứng nền loang mềm'),
            value: state.aurora,
            onChanged: (v) => state.change(() => state.aurora = v),
          ),
          _label('Phông chữ khi viết'),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0; i < kFontNames.length; i++)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(kFontNames[i],
                      style: TextStyle(fontFamily: kFontFamilies[i])),
                  selected: state.fontIndex == i,
                  selectedColor: color.fade(0.35),
                  backgroundColor: Colors.white.fade(0.06),
                  side: const BorderSide(color: Colors.white12),
                  onSelected: (_) => state.change(() => state.fontIndex = i),
                ),
            ],
          ),
          _label('Cỡ chữ: ${state.fontSize.round()}'),
          Slider(
            activeColor: color,
            min: 14,
            max: 26,
            divisions: 12,
            value: state.fontSize,
            onChanged: (v) => state.change(() => state.fontSize = v),
          ),
          _label('Giãn dòng: ${state.lineHeight.toStringAsFixed(1)}'),
          Slider(
            activeColor: color,
            min: 1.2,
            max: 2.4,
            divisions: 12,
            value: state.lineHeight,
            onChanged: (v) => state.change(() => state.lineHeight = v),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.fade(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Xem thử: Arista đứng trên đỉnh đồi nhìn xuống thung lũng sương mù.',
              style: TextStyle(
                fontSize: state.fontSize,
                height: state.lineHeight,
                fontFamily: state.fontFamily,
                color: kWhite90,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= BẢNG XUẤT FILE (dùng ở menu và ở màn soạn thảo) =================
class ExportPanel extends StatefulWidget {
  const ExportPanel({
    super.key,
    required this.state,
    required this.notesBuilder,
    required this.heading,
  });

  final AppState state;
  final List<Note> Function() notesBuilder;
  final String heading;

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  String? _message;
  bool _busy = false;

  AppState get s => widget.state;

  Future<void> _share() async {
    final notes = widget.notesBuilder();
    if (notes.isEmpty) {
      setState(() => _message = 'Chưa có bài viết để xuất.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await shareExport(s, notes);
      if (mounted) setState(() => _message = 'Đã tạo file ${s.exportFormat.label}.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Không xuất được file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final notes = widget.notesBuilder();
    if (notes.isEmpty) {
      setState(() => _message = 'Chưa có bài viết để sao chép.');
      return;
    }
    final text = exportText(s.exportFormat, notes, s.exportTitle, s.exportMeta);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _message = 'Đã sao chép dạng ${s.exportFormat.label}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final color = s.themeColor;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.heading,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ExportFormat.values)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(f.label),
                      selected: s.exportFormat == f,
                      selectedColor: color.fade(0.35),
                      backgroundColor: Colors.white.fade(0.06),
                      side: const BorderSide(color: Colors.white12),
                      onSelected: (_) => s.change(() => s.exportFormat = f),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: color,
                title: const Text('Kèm tiêu đề'),
                value: s.exportTitle,
                onChanged: (v) => s.change(() => s.exportTitle = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: color,
                title: const Text('Kèm ngày sửa và số từ'),
                value: s.exportMeta,
                onChanged: (v) => s.change(() => s.exportMeta = v),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : _share,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Chia sẻ / Lưu file'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: s.exportFormat.isText ? _copy : null,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Sao chép'),
                  ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_message!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ================= HỘP THOẠI ĐẶT MỤC TIÊU =================
class _GoalResult {
  const _GoalResult(this.goal, this.remind);
  final int goal;
  final bool remind;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({
    required this.initialGoal,
    required this.initialRemind,
    required this.themeColor,
  });

  final int initialGoal;
  final bool initialRemind;
  final Color themeColor;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialGoal.toString());
  late bool _remind = widget.initialRemind;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Nhập số từ lớn hơn 0');
      return;
    }
    Navigator.of(context).pop(_GoalResult(value, _remind));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Mục tiêu viết hàng ngày',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: widget.themeColor,
            title: const Text('Nhắc nghỉ ngơi khi viết quá mục tiêu',
                style: TextStyle(fontSize: 13)),
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
          ),
        ],
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
  const EditorScreen({super.key, this.note, required this.state});

  final Note? note;
  final AppState state;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleController;
  late final RichTextController _content;
  final FocusNode _contentFocus = FocusNode();

  int _wordCount = 0;
  String _lastCountedText = '';
  late final int _baseToday;
  bool _restDialogOpen = false;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    final text = note?.content ?? '';
    _content = RichTextController(
      text: text,
      styles: decodeStyles(note?.styles ?? '', text.length),
    );
    _lastCountedText = _content.text;
    _wordCount = countWords(_lastCountedText);
    // Số từ hôm nay không tính phần của chính bài này (để cộng số từ đang gõ).
    _baseToday = math.max(0, s.todayWords - (note?.words ?? 0));
    _content.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    final text = _content.text;
    if (text == _lastCountedText) return;
    _lastCountedText = text;
    final count = countWords(text);
    if (count != _wordCount) {
      setState(() => _wordCount = count);
      _checkRest();
    }
  }

  int get _liveToday => _baseToday + _wordCount;

  void _checkRest() {
    if (!s.restReminder || s.restShownToday || _restDialogOpen) return;
    if (_liveToday <= s.dailyGoal) return;
    s.markRestShown();
    _restDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRestDialog();
    });
  }

  Future<void> _showRestDialog() async {
    final color = s.themeColor;
    final rest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Icon(Icons.self_improvement, color: color, size: 40),
        title: const Text('Nghỉ ngơi một chút nhé',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(
          'Hôm nay bạn đã viết $_liveToday từ, vượt mục tiêu ${s.dailyGoal} từ. '
          'Hãy đứng dậy vươn vai, uống nước và cho mắt nghỉ 5-10 phút. '
          'Bài viết của bạn vẫn ở đây chờ bạn.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Viết tiếp', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu và nghỉ ngơi'),
          ),
        ],
      ),
    );
    _restDialogOpen = false;
    if (rest == true && mounted) _saveAndExit();
  }

  /// Tạo bài viết từ nội dung đang soạn (đã cắt khoảng trắng đầu/cuối,
  /// định dạng được cắt theo đúng đoạn chữ).
  Note _buildNote({required String id, required bool pinned}) {
    final raw = _content.text;
    final trimmed = raw.trim();
    final lead = raw.length - raw.trimLeft().length;
    final styles = trimmed.isEmpty
        ? ''
        : _content.encodedStylesRange(lead, lead + trimmed.length);
    final title = _titleController.text.trim();
    return Note(
      id: id,
      title: title.isEmpty ? 'Bài viết mới' : title,
      content: trimmed,
      styles: styles,
      isPinned: pinned,
      words: countWords(trimmed),
      updatedAt: DateTime.now(),
    );
  }

  void _saveAndExit() {
    final original = widget.note;
    final title = _titleController.text.trim();
    final content = _content.text.trim();

    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final saved = _buildNote(
      id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      pinned: original?.isPinned ?? false,
    );

    if (original != null &&
        original.title == saved.title &&
        original.content == saved.content &&
        original.styles == saved.styles) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(saved);
  }

  void _openExport() {
    final note = _buildNote(id: widget.note?.id ?? 'draft', pinned: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF14141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Xuất bài viết này',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ExportPanel(
                state: s,
                notesBuilder: () => [note],
                heading: '"${note.title}" · ${note.words} từ',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _content.removeListener(_onContentChanged);
    _titleController.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = s.themeColor;
    final over = s.restReminder && _liveToday > s.dailyGoal;
    final readMinutes = (_wordCount / 200).ceil();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _saveAndExit();
      },
      child: Stack(
        children: [
          AuroraBackground(
            color: color,
            base: s.bgColor,
            enabled: s.aurora,
            intensity: 0.7,
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
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
              actions: [
                IconButton(
                  tooltip: 'Xuất file',
                  icon: const Icon(Icons.ios_share, color: Colors.white70),
                  onPressed: _openExport,
                ),
                IconButton(
                  tooltip: 'Lưu',
                  icon: Icon(Icons.check, color: color, size: 28),
                  onPressed: _saveAndExit,
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _titleController,
                            autofocus: widget.note == null,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Tiêu đề chương / bài viết...',
                              hintStyle: TextStyle(color: Colors.white30),
                              border: InputBorder.none,
                            ),
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _chip('$_wordCount từ', color, bold: true),
                                const SizedBox(width: 8),
                                _chip('${_content.text.length} ký tự', Colors.white54),
                                if (_wordCount > 0) ...[
                                  const SizedBox(width: 8),
                                  _chip('~$readMinutes phút đọc', Colors.white54),
                                ],
                                if (over) ...[
                                  const SizedBox(width: 8),
                                  _chip('Vượt mục tiêu · nghỉ chút nhé', Colors.amber,
                                      bold: true),
                                ],
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          Expanded(
                            child: TextField(
                              controller: _content,
                              focusNode: _contentFocus,
                              maxLines: null,
                              expands: true,
                              keyboardType: TextInputType.multiline,
                              cursorColor: color,
                              textAlignVertical: TextAlignVertical.top,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(
                                fontSize: s.fontSize,
                                color: kWhite90,
                                height: s.lineHeight,
                                fontFamily: s.fontFamily,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Bắt đầu đặt bút thả hồn vào câu chuyện...',
                                hintStyle: TextStyle(color: Colors.white24),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildToolbar(color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.fade(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildToolbar(Color color) {
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: ListenableBuilder(
          listenable: _content,
          builder: (context, _) {
            final block = _content.activeBlock;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolBtn(
                    icon: Icons.undo,
                    tooltip: 'Hoàn tác',
                    color: color,
                    enabled: _content.canUndo,
                    onTap: _content.undo,
                  ),
                  _ToolBtn(
                    icon: Icons.redo,
                    tooltip: 'Làm lại',
                    color: color,
                    enabled: _content.canRedo,
                    onTap: _content.redo,
                  ),
                  const _ToolDivider(),
                  _ToolBtn(
                    icon: Icons.format_bold,
                    tooltip: 'In đậm',
                    color: color,
                    active: _content.isInlineActive(kBold),
                    onTap: () => _content.toggleInline(kBold),
                  ),
                  _ToolBtn(
                    icon: Icons.format_italic,
                    tooltip: 'In nghiêng',
                    color: color,
                    active: _content.isInlineActive(kItalic),
                    onTap: () => _content.toggleInline(kItalic),
                  ),
                  _ToolBtn(
                    icon: Icons.format_underlined,
                    tooltip: 'Gạch chân',
                    color: color,
                    active: _content.isInlineActive(kUnderline),
                    onTap: () => _content.toggleInline(kUnderline),
                  ),
                  _ToolBtn(
                    icon: Icons.format_strikethrough,
                    tooltip: 'Gạch ngang',
                    color: color,
                    active: _content.isInlineActive(kStrike),
                    onTap: () => _content.toggleInline(kStrike),
                  ),
                  const _ToolDivider(),
                  _ToolBtn(
                    label: 'H1',
                    tooltip: 'Tiêu đề lớn',
                    color: color,
                    active: block == 1,
                    onTap: () => _content.setBlock(1),
                  ),
                  _ToolBtn(
                    label: 'H2',
                    tooltip: 'Tiêu đề vừa',
                    color: color,
                    active: block == 2,
                    onTap: () => _content.setBlock(2),
                  ),
                  _ToolBtn(
                    label: 'H3',
                    tooltip: 'Tiêu đề nhỏ',
                    color: color,
                    active: block == 3,
                    onTap: () => _content.setBlock(3),
                  ),
                  const _ToolDivider(),
                  _ToolBtn(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Gạch đầu dòng',
                    color: color,
                    onTap: _content.toggleBullet,
                  ),
                  _ToolBtn(
                    icon: Icons.format_clear,
                    tooltip: 'Xóa định dạng',
                    color: color,
                    onTap: _content.clearFormatting,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white12,
      );
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    this.icon,
    this.label,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? Colors.white24 : (active ? color : Colors.white70);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 42,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? color.fade(0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 21, color: fg)
              : Text(label ?? '',
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
    );
  }
}
