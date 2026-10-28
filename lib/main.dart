import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  final List<Note> _notes = _sampleNotes();

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

  void _nextThemeColor() {
    final index = kThemeColors.indexOf(widget.themeColor);
    widget.onThemeChanged(kThemeColors[(index + 1) % kThemeColors.length]);
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
          n.content.toLowerCase().contains(query);
    }).toList();

    final todayWords = _todayWords;
    final ratio = _dailyGoal > 0 ? todayWords / _dailyGoal : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;

    return Scaffold(
      body: Stack(
        children: [
          // QUẦNG SÁNG RADIAL GRADIENT MỜ MỊN
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.themeColor.fade(0.45),
                    widget.themeColor.fade(0.15),
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
                tooltip: 'Đổi màu chủ đề',
                icon: const Icon(Icons.star_outline,
                    color: Colors.amber, size: 20),
                onPressed: _nextThemeColor,
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
      note.content.isEmpty
          ? '(Chưa có nội dung)'
          : previewText(note.content),
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
                Text('${note.words} từ',
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
  });

  final Note? note;
  final Color themeColor;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  int _wordCount = 0;
  String _lastCountedText = '';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _lastCountedText = _contentController.text;
    _wordCount = countWords(_lastCountedText);
    _contentController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    final text = _contentController.text;
    // Listener cũng chạy khi chỉ di chuyển con trỏ, bỏ qua nếu chữ không đổi.
    if (text == _lastCountedText) return;
    _lastCountedText = text;
    final count = countWords(text);
    if (count != _wordCount) {
      setState(() {
        _wordCount = count;
      });
    }
  }

  void _saveAndExit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final original = widget.note;

    // Không có gì để lưu.
    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final finalTitle = title.isEmpty ? 'Bài viết mới' : title;

    // Không thay đổi gì thì không cần lưu (giữ nguyên ngày sửa cũ).
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
      words: countWords(content),
      updatedAt: now,
    );

    Navigator.of(context).pop(saved);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PopScope: nút Back của điện thoại / vuốt quay lại cũng tự lưu bài viết,
    // tránh mất chữ vừa gõ.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08080A),
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
              tooltip: 'Lưu',
              icon: Icon(Icons.check, color: widget.themeColor, size: 28),
              onPressed: _saveAndExit,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.themeColor.fade(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_wordCount từ',
                        style: TextStyle(
                            color: widget.themeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 24),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontSize: 16, color: kWhite90, height: 1.6),
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
      ),
    );
  }
}
