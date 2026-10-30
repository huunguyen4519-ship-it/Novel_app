import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const NovelApp());
}

// ================= TIỆN ÍCH =================

/// Các màu chủ đề, chọn trong menu ngôi sao.
const List<Color> kThemeColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFA855F7),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

/// Màu chữ trắng đục 90%.
const Color kWhite90 = Color(0xE6FFFFFF);

/// Số ngày giữ bài trong thùng rác trước khi xóa vĩnh viễn.
const int kTrashDays = 30;

/// Chỉ tiêu mặc định (số từ) cho mỗi thẻ.
const int kDefaultGoal = 500;

extension ColorFade on Color {
  /// Trả về màu này với độ đục [opacity] (0.0 - 1.0).
  Color fade(double opacity) =>
      withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

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
      unit == 0x3000 ||
      unit == 0x200B ||
      unit == 0xFEFF;
}

/// HÀM ĐẾM TỪ DUY NHẤT của cả app (thẻ, màn soạn thảo, chỉ tiêu đều dùng
/// hàm này nên số luôn khớp nhau). Chỉ đếm chữ thật: dấu cách, xuống dòng,
/// dòng trống đều chỉ là chỗ ngắt, không bao giờ tính thành một từ.
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

/// Cắt đoạn xem trước để thẻ bài viết không phải dàn trang cả chương dài.
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

// ================= MODEL BÀI VIẾT =================

class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    this.isPinned = false,
    required this.updatedAt,
    this.deletedAt,
    this.restored = false,
    this.goalTarget = kDefaultGoal,
  }) : words = countWords(content);

  final String id;
  final String title;
  final String content;
  final bool isPinned;
  final DateTime updatedAt;

  /// Thời điểm bị xóa (null = bài đang dùng bình thường).
  final DateTime? deletedAt;

  /// Đã từng được khôi phục từ thùng rác (hiện ký hiệu tái chế).
  final bool restored;

  /// Số từ, luôn tính từ nội dung bằng [countWords].
  final int words;

  /// Chỉ tiêu số từ riêng của thẻ này (dùng khi thẻ là thẻ mục tiêu).
  final int goalTarget;

  Note copyWith({
    String? title,
    String? content,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeleted = false,
    bool? restored,
    int? goalTarget,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      isPinned: isPinned ?? this.isPinned,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      restored: restored ?? this.restored,
      goalTarget: goalTarget ?? this.goalTarget,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'pinned': isPinned,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'restored': restored,
        'goalTarget': goalTarget,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      isPinned: (json['pinned'] as bool?) ?? false,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
              DateTime.now(),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'] as String),
      restored: (json['restored'] as bool?) ?? false,
      goalTarget: (json['goalTarget'] as int?) ?? kDefaultGoal,
    );
  }
}

/// Số ngày còn lại trước khi bài trong thùng rác bị xóa vĩnh viễn.
int trashDaysLeft(Note note) {
  final deleted = note.deletedAt;
  if (deleted == null) return kTrashDays;
  final elapsed = DateTime.now().difference(deleted).inDays;
  final left = kTrashDays - elapsed;
  return left < 0 ? 0 : left;
}

bool isTrashExpired(Note note) {
  final deleted = note.deletedAt;
  if (deleted == null) return false;
  return DateTime.now().difference(deleted) >= const Duration(days: kTrashDays);
}

List<Note> _sampleNotes() {
  final now = DateTime.now();
  const welcome =
      'Chào mừng bạn đến với ứng dụng Novel App! Nhấn nút cộng ở góc dưới để '
      'tạo bài viết mới hoặc nhấn vào bài này để chỉnh sửa. Nhấn giữ một bài '
      'để đặt làm mục tiêu hoặc xóa. Nhấn vào ngôi sao ở góc trên để tùy chỉnh '
      'giao diện, xuất file, mở thùng rác và xem chuỗi ngày viết liên tục.';
  const chapter =
      'Arista Valerius đứng trên đỉnh ngọn đồi nhìn xuống thung lũng sương mù...';

  return [
    Note(
      id: '1',
      title: 'Ý tưởng tiểu thuyết mới',
      content: welcome,
      isPinned: true,
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
    Note(
      id: '2',
      title: 'Con đường của ánh sáng - Chương 1',
      content: chapter,
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
  ];
}

List<Note> _decodeNotes(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}

String _encodeNotes(List<Note> notes) =>
    jsonEncode(notes.map((n) => n.toJson()).toList());

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt('theme');
      if (value != null && mounted) {
        setState(() {
          _themeColor = Color(value);
        });
      }
    } catch (_) {}
  }

  Future<void> _changeThemeColor(Color color) async {
    setState(() {
      _themeColor = color;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme', color.value);
    } catch (_) {}
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
  String _searchQuery = '';

  // Thẻ mục tiêu: mỗi lúc chỉ có 1 thẻ. Chỉ tiêu được lưu ngay trên từng thẻ.
  String? _goalNoteId;

  // Điểm danh chuỗi: số ngày liên tiếp có viết thêm nội dung.
  int _streakDays = 0;
  DateTime? _lastStreakDate;

  final List<Note> _notes = [];
  final List<Note> _trash = [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------- Lưu / tải dữ liệu ----------

  Future<void> _load() async {
    var notes = <Note>[];
    var trash = <Note>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      final rawNotes = prefs.getString('notes');
      notes = rawNotes == null ? _sampleNotes() : _decodeNotes(rawNotes);

      final rawTrash = prefs.getString('trash');
      if (rawTrash != null) trash = _decodeNotes(rawTrash);

      _goalNoteId = prefs.getString('goalNoteId');
      
      // Chuyển chỉ tiêu cũ (một con số dùng chung) sang thẻ mục tiêu, chỉ làm một lần.
      final legacyTarget = prefs.getInt('goalTarget');
      if (legacyTarget != null &&
          !(prefs.getBool('goalTargetMigrated') ?? false)) {
        for (var i = 0; i < notes.length; i++) {
          if (notes[i].id == _goalNoteId) {
            notes[i] = notes[i].copyWith(goalTarget: legacyTarget);
          }
        }
        await prefs.setBool('goalTargetMigrated', true);
      }

      _streakDays = prefs.getInt('streakDays') ?? 0;
      final last = prefs.getString('lastStreak');
      _lastStreakDate = last == null ? null : DateTime.tryParse(last);
    } catch (_) {
      if (notes.isEmpty) notes = _sampleNotes();
    }

    if (!mounted) return;
    setState(() {
      _notes
        ..clear()
        ..addAll(notes);
      _trash
        ..clear()
        ..addAll(trash);
      _purgeExpiredTrash();
      _sortNotes();
    });
    _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString('notes', _encodeNotes(_notes));
      await prefs.setString('trash', _encodeNotes(_trash));

      final goalId = _goalNoteId;
      if (goalId == null) {
        await prefs.remove('goalNoteId');
      } else {
        await prefs.setString('goalNoteId', goalId);
      }

      await prefs.setInt('streakDays', _streakDays);
      final last = _lastStreakDate;
      if (last == null) {
        await prefs.remove('lastStreak');
      } else {
        await prefs.setString('lastStreak', last.toIso8601String());
      }
    } catch (_) {}
  }

  /// Xóa vĩnh viễn các bài đã nằm trong thùng rác quá 30 ngày.
  void _purgeExpiredTrash() {
    _trash.removeWhere(isTrashExpired);
  }

  // ---------- Mục tiêu ----------

  Note? get _goalNote {
    final id = _goalNoteId;
    if (id == null) return null;
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _setGoal(Note note) {
    setState(() {
      _goalNoteId = note.id;
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã đặt "${_titleOf(note)}" làm thẻ mục tiêu.')),
    );
  }

  void _clearGoal() {
    setState(() {
      _goalNoteId = null;
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã hủy thẻ mục tiêu.')),
    );
  }

  String _titleOf(Note note) =>
      note.title.isEmpty ? 'Không có tiêu đề' : note.title;

  void _recordStreak(DateTime today) {
    final last = _lastStreakDate;
    if (last == null) {
      _streakDays = 1;
    } else if (last == today) {
      // đã tính hôm nay rồi, không cộng thêm
    } else if (last == today.subtract(const Duration(days: 1))) {
      _streakDays += 1;
    } else {
      _streakDays = 1;
    }
    _lastStreakDate = today;
  }

  // ---------- Hộp thoại ----------

  void _showRestReminder() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.self_improvement, color: Colors.amber),
            SizedBox(width: 8),
            Text('Đã đạt chỉ tiêu!',
                style: TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
        content: const Text(
          'Thẻ mục tiêu đã đủ số từ. Hãy nghỉ ngơi một chút, uống nước và '
          'thư giãn mắt. Bạn có thể chọn thẻ khác làm mục tiêu mới.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Đã hiểu', style: TextStyle(color: widget.themeColor)),
          ),
        ],
      ),
    );
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
    final goalNote = _goalNote;
    if (goalNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhấn giữ một thẻ để đặt làm mục tiêu.')),
      );
      return;
    }
    final target = await showDialog<int>(
      context: context,
      builder: (context) => _GoalDialog(
        initialGoal: goalNote.goalTarget,
        themeColor: widget.themeColor,
      ),
    );
    if (target == null || !mounted) return;
    setState(() {
      final index = _notes.indexWhere((n) => n.id == goalNote.id);
      if (index >= 0) {
        _notes[index] = _notes[index].copyWith(goalTarget: target);
      }
    });
    _persist();
  }

  /// Menu ngôi sao: đổi màu, xuất file, thùng rác, chuỗi ngày.
  void _openStarMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _StarMenuSheet(
        themeColor: widget.themeColor,
        onThemeSelected: widget.onThemeChanged,
        streakDays: _streakDays,
        lastStreakDate: _lastStreakDate,
        notes: List<Note>.of(_notes),
        trashCount: _trash.length,
        onOpenTrash: _openTrash,
      ),
    );
  }

  // ---------- Thùng rác ----------

  void _openTrash() {
    setState(_purgeExpiredTrash);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrashScreen(
          trash: _trash,
          themeColor: widget.themeColor,
          onRestore: _restoreNote,
          onDeleteForever: _deleteForever,
          onEmpty: _emptyTrash,
        ),
      ),
    );
  }

  void _restoreNote(Note note) {
    setState(() {
      _trash.removeWhere((n) => n.id == note.id);
      _notes.add(note.copyWith(clearDeleted: true, restored: true));
      _sortNotes();
    });
    _persist();
  }

  void _deleteForever(Note note) {
    setState(() {
      _trash.removeWhere((n) => n.id == note.id);
    });
    _persist();
  }

  void _emptyTrash() {
    setState(() {
      _trash.clear();
    });
    _persist();
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
          '"${_titleOf(note)}" sẽ được chuyển vào thùng rác và giữ trong '
          '$kTrashDays ngày. Bạn có thể khôi phục trong thời gian đó.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
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
      _trash.insert(0, note.copyWith(deletedAt: DateTime.now()));
      if (_goalNoteId == note.id) _goalNoteId = null;
    });
    _persist();
  }

  // ---------- Menu nhấn giữ thẻ ----------

  void _openNoteMenu(Note note) {
    final isGoal = note.id == _goalNoteId;
    final subtitle = isGoal
        ? 'Thanh chỉ tiêu đang đếm theo thẻ này. Chỉ tiêu: ${note.goalTarget} từ.'
        : 'Chỉ tiêu: ${note.goalTarget} từ. Đặt làm mục tiêu để đếm theo thẻ này.';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16161C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _titleOf(note),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Text('🐉', style: TextStyle(fontSize: 26)),
                title: Text(
                    isGoal ? 'hủy mục tiêu' : 'đặt thẻ này làm mục tiêu?',
                    style: const TextStyle(fontSize: 13, color: Colors.white)),
                subtitle: Text(subtitle,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white54)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (isGoal) {
                    _clearGoal();
                  } else {
                    _setGoal(note);
                  }
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Xóa thẻ (chuyển vào thùng rác)',
                    style: TextStyle(fontSize: 13, color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(note);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Soạn thảo ----------

  Future<void> _openEditor([Note? note]) async {
    final goalNote = (note != null && note.id == _goalNoteId) ? note : null;

    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute<Note>(
        builder: (context) => EditorScreen(
          note: note,
          themeColor: widget.themeColor,
          goalTarget: goalNote?.goalTarget,
        ),
      ),
    );

    if (result == null || !mounted) return;

    var reachedGoal = false;
    setState(() {
      final index = _notes.indexWhere((n) => n.id == result.id);
      final oldWords = index >= 0 ? _notes[index].words : 0;

      if (index >= 0) {
        _notes[index] = result;
      } else {
        _notes.add(result);
      }

      if (result.words > oldWords) {
        _recordStreak(dateOnly(DateTime.now()));
      }

      if (result.id == _goalNoteId &&
          oldWords < result.goalTarget &&
          result.words >= result.goalTarget) {
        reachedGoal = true;
      }

      _sortNotes();
    });
    _persist();

    if (reachedGoal) _showRestReminder();
  }

  void _togglePin(String id) {
    setState(() {
      final index = _notes.indexWhere((n) => n.id == id);
      if (index < 0) return;
      _notes[index] = _notes[index].copyWith(isPinned: !_notes[index].isPinned);
      _sortNotes();
    });
    _persist();
  }

  /// Bài ghim lên trước, sau đó bài sửa gần nhất lên trước.
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
          n.content.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          _SoftBackground(themeColor: widget.themeColor),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(),
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

  Widget _buildHeader() {
    final goal = _goalNote;
    final goalWords = goal?.words ?? 0;
    
    final target = goal?.goalTarget ?? kDefaultGoal;
    final ratio = target > 0 ? goalWords / target : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;

    final line1 = goal == null
        ? 'chào mừng đã đến với app'
        : '🐉 ${_titleOf(goal)}';
    final line2 = goal == null
        ? 'Nhấn giữ một thẻ để đặt làm mục tiêu'
        : '$goalWords / $target từ';

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
                tooltip: 'Tùy chỉnh, xuất file & thùng rác',
                icon: const Icon(Icons.star_outline,
                    color: Colors.amber, size: 20),
                onPressed: _openStarMenu,
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
                  Text(line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(line2,
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
    final isGoal = note.id == _goalNoteId;
    final contentText = Text(
      note.content.isEmpty ? '(Chưa có nội dung)' : previewText(note.content),
      maxLines: _isGridMode ? 3 : 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white60, fontSize: 13),
    );

    return GestureDetector(
      key: key,
      onTap: () => _openEditor(note),
      onLongPress: () => _openNoteMenu(note),
      child: Container(
        margin: EdgeInsets.only(bottom: _isGridMode ? 0 : 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.fade(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isGoal
                ? Colors.amber.fade(0.7)
                : (note.isPinned
                    ? widget.themeColor.fade(0.5)
                    : Colors.white10),
          ),
        ),
        child: Column(
          mainAxisSize: _isGridMode ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isGoal)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text('🐉', style: TextStyle(fontSize: 14)),
                  ),
                if (note.restored)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.recycling,
                        size: 15, color: Colors.lightGreenAccent),
                  ),
                Expanded(
                  child: Text(
                    _titleOf(note),
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
            if (_isGridMode) Expanded(child: contentText) else contentText,
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isGoal
                      ? '${note.words} / ${note.goalTarget} từ'
                      : '${note.words} từ',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                Text(
                  formatDate(note.updatedAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= NỀN LOANG MỀM MẠI =================

class _SoftBackground extends StatelessWidget {
  const _SoftBackground({required this.themeColor});

  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final accent = HSLColor.fromColor(themeColor)
        .withHue((HSLColor.fromColor(themeColor).hue + 40) % 360)
        .toColor();

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              top: -160,
              left: -120,
              child: _blob(themeColor, 420),
            ),
            Positioned(
              top: -80,
              right: -160,
              child: _blob(accent, 360),
            ),
            Positioned(
              bottom: -200,
              left: -100,
              child: _blob(themeColor.fade(0.7), 320),
            ),
            // Lớp phủ tối nhẹ phía dưới để chữ luôn dễ đọc.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF08080A).fade(0.4),
                    const Color(0xFF08080A).fade(0.85),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.fade(0.55),
              color.fade(0.28),
              color.fade(0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

// ================= HỘP THOẠI CHỈ TIÊU =================

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Chỉ tiêu của thẻ mục tiêu',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              suffixText: 'từ',
              suffixStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thẻ mục tiêu đạt đủ số từ này thì app sẽ nhắc bạn nghỉ ngơi.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () {
            final value = int.tryParse(_controller.text.trim());
            Navigator.pop(context, (value == null || value <= 0) ? 1 : value);
          },
          child: Text('Lưu', style: TextStyle(color: widget.themeColor)),
        ),
      ],
    );
  }
}

// ================= MENU NGÔI SAO =================

enum _ExportFormat { txt, markdown }

/// Bảng tùy chọn khi bấm ngôi sao: đổi giao diện, thùng rác, xuất file, chuỗi.
class _StarMenuSheet extends StatefulWidget {
  const _StarMenuSheet({
    required this.themeColor,
    required this.onThemeSelected,
    required this.streakDays,
    required this.lastStreakDate,
    required this.notes,
    required this.trashCount,
    required this.onOpenTrash,
  });

  final Color themeColor;
  final ValueChanged<Color> onThemeSelected;
  final int streakDays;
  final DateTime? lastStreakDate;
  final List<Note> notes;
  final int trashCount;
  final VoidCallback onOpenTrash;

  @override
  State<_StarMenuSheet> createState() => _StarMenuSheetState();
}

class _StarMenuSheetState extends State<_StarMenuSheet> {
  Note? _exportNote;
  _ExportFormat _format = _ExportFormat.txt;

  @override
  void initState() {
    super.initState();
    _exportNote = widget.notes.isNotEmpty ? widget.notes.first : null;
  }

  String get _extension => _format == _ExportFormat.markdown ? 'md' : 'txt';

  String _buildExportText() {
    final notesToExport = _exportNote == null ? widget.notes : [_exportNote!];
    final buffer = StringBuffer();
    for (final note in notesToExport) {
      final title = note.title.isEmpty ? 'Không có tiêu đề' : note.title;
      if (_format == _ExportFormat.markdown) {
        buffer.writeln('# $title');
        buffer.writeln();
        buffer.writeln(note.content);
        buffer.writeln();
      } else {
        buffer.writeln(title);
        buffer.writeln('-' * 20);
        buffer.writeln(note.content);
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  /// Tên file an toàn: bỏ ký tự cấm, giới hạn độ dài.
  String _buildFileName() {
    var base = _exportNote == null
        ? 'novel_app_tat_ca_bai_viet'
        : (_exportNote!.title.isEmpty ? 'bai_viet' : _exportNote!.title);
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();
    if (base.isEmpty) base = 'bai_viet';
    if (base.length > 60) base = base.substring(0, 60);
    return '$base.$_extension';
  }

  /// Xuất ra FILE thật (.txt / .md) vào thư mục Download của điện thoại.
  /// Nếu máy không cho ghi vào đó thì tự động sao chép nội dung vào bộ nhớ tạm.
  Future<void> _exportFile() async {
    final text = _buildExportText();
    final fileName = _buildFileName();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text, encoding: utf8);
      messenger.showSnackBar(
        SnackBar(content: Text('Đã lưu file vào thư mục Download: $fileName')),
      );
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Máy không cho lưu file trực tiếp. Đã sao chép nội dung vào bộ nhớ tạm, bạn dán vào ghi chú rồi lưu nhé.'),
        ),
      );
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _buildExportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép nội dung vào bộ nhớ tạm.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streakText = widget.streakDays <= 0
        ? 'Hãy viết hôm nay để bắt đầu chuỗi!'
        : '🔥 ${widget.streakDays} ngày viết liên tiếp';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF16161C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
              const SizedBox(height: 18),
              const Text('Tùy chỉnh & xuất file',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // --- Điểm danh chuỗi ---
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.themeColor.fade(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: widget.themeColor.fade(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Colors.orangeAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(streakText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // --- Thùng rác ---
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenTrash();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.fade(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          color: Colors.lightGreenAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Thùng rác (${widget.trashCount})',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // --- Màu chủ đề ---
              const Text('Màu chủ đề',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: kThemeColors.map((color) {
                  final selected = color.value == widget.themeColor.value;
                  return GestureDetector(
                    onTap: () => widget.onThemeSelected(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              // --- Xuất file ---
              const Text('Xuất file',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              DropdownButtonFormField<Note?>(
                value: _exportNote,
                isExpanded: true,
                dropdownColor: const Color(0xFF1F1F27),
                decoration: const InputDecoration(
                  labelText: 'Chọn bài viết',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
                style: const TextStyle(color: Colors.white),
                items: [
                  const DropdownMenuItem<Note?>(
                    value: null,
                    child: Text('Tất cả bài viết'),
                  ),
                  ...widget.notes.map(
                    (n) => DropdownMenuItem<Note?>(
                      value: n,
                      child: Text(
                        n.title.isEmpty ? 'Không có tiêu đề' : n.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _exportNote = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _formatChip('TXT (văn bản)', _ExportFormat.txt),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                        _formatChip('Markdown (.md)', _ExportFormat.markdown),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.themeColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: widget.notes.isEmpty ? null : _exportFile,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text('Xuất file .$_extension'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: widget.notes.isEmpty ? null : _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Chỉ sao chép nội dung'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bấm "Xuất file" để lưu file vào thư mục Download. Nếu máy không '
                'cho phép, nội dung sẽ được sao chép vào bộ nhớ tạm.',
                style:
                    TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _formatChip(String label, _ExportFormat value) {
    final selected = _format == value;
    return GestureDetector(
      onTap: () => setState(() => _format = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected ? widget.themeColor.fade(0.25) : Colors.white.fade(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? widget.themeColor : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ================= MÀN HÌNH THÙNG RÁC =================

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    super.key,
    required this.trash,
    required this.themeColor,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onEmpty,
  });

  final List<Note> trash;
  final Color themeColor;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;
  final VoidCallback onEmpty;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  Future<void> _confirmDeleteForever(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Xóa vĩnh viễn?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Bài viết này sẽ mất và không thể khôi phục.',
            style: TextStyle(color: Colors.white70)),
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
    if (ok != true || !mounted) return;
    widget.onDeleteForever(note);
    setState(() {});
  }

  Future<void> _confirmEmpty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Dọn sạch thùng rác?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Tất cả bài trong thùng rác sẽ mất vĩnh viễn.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dọn sạch',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.onEmpty();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.trash;
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Thùng rác', style: TextStyle(fontSize: 16)),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: _confirmEmpty,
              child: const Text('Dọn sạch',
                  style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                'Thùng rác trống.\nBài bị xóa được giữ 30 ngày.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, height: 1.5),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final note = items[index];
                final left = trashDaysLeft(note);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.fade(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              note.title.isEmpty
                                  ? 'Không có tiêu đề'
                                  : note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${note.words} từ · còn $left ngày',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: left <= 3
                                      ? Colors.redAccent
                                      : Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Khôi phục',
                        icon: const Icon(Icons.recycling,
                            color: Colors.lightGreenAccent),
                        onPressed: () {
                          widget.onRestore(note);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Đã khôi phục bài viết.')),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Xóa vĩnh viễn',
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.redAccent),
                        onPressed: () => _confirmDeleteForever(note),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ================= MÀN HÌNH SOẠN THẢO =================

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.note,
    required this.themeColor,
    this.goalTarget,
  });

  final Note? note;
  final Color themeColor;
  
  /// Chỉ tiêu của thẻ này nếu nó đang là thẻ mục tiêu (null = không phải).
  final int? goalTarget;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _contentController =
      TextEditingController(text: widget.note?.content ?? '');

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text;
    final title = _titleController.text.trim();
    final old = widget.note;
    final Note note;

    if (old == null) {
      note = Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      );
    } else {
      note = old.copyWith(
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      );
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.goalTarget;
    
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Bộ đếm lắng nghe trực tiếp controller nên cập nhật ở MỌI thay đổi
        // (gõ, xóa, dán, bộ gõ tiếng Việt...). Dùng chung hàm countWords với
        // thẻ ngoài màn hình chính nên số luôn khớp.
        title: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _contentController,
          builder: (context, value, _) {
            final words = countWords(value.text);
            final text = target == null
                ? '$words từ'
                : '🐉 $words / $target từ';

            return Text(
              text,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Lưu',
            icon: Icon(Icons.check, color: widget.themeColor),
            onPressed: _save,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Tiêu đề...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                      fontSize: 15, color: kWhite90, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Bắt đầu viết câu chuyện của bạn...',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
