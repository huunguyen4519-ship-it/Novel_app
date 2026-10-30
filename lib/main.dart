import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
      unit == 0x3000;
}

/// Đếm số từ trong [text]. Duyệt từng ký tự, không tạo danh sách trung gian
/// nên vẫn nhanh khi chương truyện rất dài.
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
      'viết để xóa. Nhấn vào ngôi sao ở góc trên để tùy chỉnh giao diện, '
      'xuất file và xem chuỗi ngày viết liên tục của bạn.';
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

  void _changeThemeColor(Color color) {
    setState(() {
      _themeColor = color;
    });
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

  // Số từ viết thêm trong ngày (tự về 0 khi sang ngày mới).
  int _wordsToday = 0;
  DateTime _goalDay = dateOnly(DateTime.now());
  bool _restReminderShownToday = false;

  // Điểm danh chuỗi: số ngày liên tiếp có viết thêm nội dung.
  int _streakDays = 0;
  DateTime? _lastStreakDate;

  final List<Note> _notes = _sampleNotes();

  int get _todayWords =>
      dateOnly(DateTime.now()) == _goalDay ? _wordsToday : 0;

  void _addWordsToday(int delta) {
    final today = dateOnly(DateTime.now());
    if (today != _goalDay) {
      _goalDay = today;
      _wordsToday = 0;
      _restReminderShownToday = false;
    }
    final wasUnderGoal = _wordsToday < _dailyGoal;
    final next = _wordsToday + delta;
    _wordsToday = next < 0 ? 0 : next;

    if (delta > 0) {
      _recordStreak(today);
    }

    // Lời nhắc nghỉ ngơi khi vừa vượt qua mục tiêu từ trong ngày.
    if (wasUnderGoal &&
        _wordsToday >= _dailyGoal &&
        !_restReminderShownToday) {
      _restReminderShownToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRestReminder();
      });
    }
  }

  void _recordStreak(DateTime today) {
    if (_lastStreakDate == null) {
      _streakDays = 1;
    } else if (_lastStreakDate == today) {
      // đã tính hôm nay rồi, không cộng thêm
    } else if (_lastStreakDate == today.subtract(const Duration(days: 1))) {
      _streakDays += 1;
    } else {
      _streakDays = 1;
    }
    _lastStreakDate = today;
  }

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
            Text('Đã đạt mục tiêu!',
                style: TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
        content: const Text(
          'Bạn đã viết đủ mục tiêu từ hôm nay rồi. Hãy nghỉ ngơi một chút, '
          'uống nước và thư giãn mắt trước khi viết tiếp nhé.',
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
      _restReminderShownToday =
          _wordsToday < _dailyGoal ? false : _restReminderShownToday;
    });
  }

  /// Menu ngôi sao: luôn hiện bảng tùy chọn (đổi màu, xuất file, chuỗi ngày).
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
        notes: _notes,
      ),
    );
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
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      final index = _notes.indexWhere((n) => n.id == result.id);
      if (index >= 0) {
        _addWordsToday(result.words - _notes[index].words);
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

    final todayWords = _todayWords;
    final ratio = _dailyGoal > 0 ? todayWords / _dailyGoal : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;

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
                tooltip: 'Tùy chỉnh & xuất file',
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
      note.content.isEmpty ? '(Chưa có nội dung)' : previewText(note.content),
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
            if (_isGridMode) Expanded(child: contentText) else contentText,
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${note.words} từ',
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
      title: const Text('Mục tiêu viết mỗi ngày',
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
              suffixText: 'từ / ngày',
              suffixStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Khi viết đạt hoặc vượt mục tiêu, app sẽ nhắc bạn nghỉ ngơi.',
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

/// Bảng tùy chọn khi bấm ngôi sao: đổi giao diện, xuất file, điểm danh chuỗi.
class _StarMenuSheet extends StatefulWidget {
  const _StarMenuSheet({
    required this.themeColor,
    required this.onThemeSelected,
    required this.streakDays,
    required this.lastStreakDate,
    required this.notes,
  });

  final Color themeColor;
  final ValueChanged<Color> onThemeSelected;
  final int streakDays;
  final DateTime? lastStreakDate;
  final List<Note> notes;

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

  /// Xuất ra FILE thật (.txt / .md) và mở bảng chia sẻ của hệ điều hành,
  /// nơi người dùng chọn "Lưu vào Tệp / Drive / Zalo / Email...".
  Future<void> _exportFile() async {
    final text = _buildExportText();
    final fileName = _buildFileName();
    final mime = _format == _ExportFormat.markdown
        ? 'text/markdown'
        : 'text/plain';
    try {
      final dir = await Directory.systemTemp.createTemp('novel_export');
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text, encoding: utf8);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mime, name: fileName)],
        subject: fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không xuất được file. Bạn thử nút "Sao chép" nhé.'),
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
      initialChildSize: 0.78,
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
                'Sau khi bấm "Xuất file", chọn nơi lưu trong bảng chia sẻ '
                '(Lưu vào Tệp, Google Drive, Zalo, Email...).',
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

// ================= MÀN HÌNH SOẠN THẢO =================
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.note, required this.themeColor});

  final Note? note;
  final Color themeColor;

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
    final note = Note(
      id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      content: content,
      isPinned: widget.note?.isPinned ?? false,
      words: countWords(content),
      updatedAt: DateTime.now(),
    );
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // SỬA LỖI BỘ ĐẾM: ValueListenableBuilder lắng nghe trực tiếp
        // controller, nên số từ được tính lại và vẽ lại ở MỖI lần nội dung
        // thay đổi (gõ, xóa, dán, bộ gõ tiếng Việt...), không phụ thuộc
        // vào setState thủ công.
        title: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _contentController,
          builder: (context, value, _) {
            return Text(
              '${countWords(value.text)} từ',
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
