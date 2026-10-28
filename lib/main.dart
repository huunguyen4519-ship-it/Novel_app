import 'package:flutter/material.dart';

void main() {
  runApp(const NovelApp());
}

// ================= MODEL BÀI VIẾT =================
class Note {
  String id;
  String title;
  String content;
  bool isPinned;
  int words;
  String date;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.isPinned = false,
    required this.words,
    required this.date,
  });
}

// ================= GỐC ỨNG DỤNG =================
class NovelApp extends StatefulWidget {
  const NovelApp({super.key});

  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  Color _themeColor = const Color(0xFFEF4444);

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
  final Color themeColor;
  final ValueChanged<Color> onThemeChanged;

  const HomeScreen({
    super.key,
    required this.themeColor,
    required this.onThemeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridMode = true;
  int _dailyGoal = 500;
  String _searchQuery = '';

  final List<Note> _notes = [
    Note(
      id: '1',
      title: 'Ý tưởng tiểu thuyết mới',
      content:
          'Chào mừng bạn đến với ứng dụng Novel App! Nhấn nút cộng ở góc dưới để tạo bài viết mới hoặc nhấn vào bài này để chỉnh sửa.',
      isPinned: true,
      words: 32,
      date: '27/10',
    ),
    Note(
      id: '2',
      title: 'Con đường của ánh sáng - Chương 1',
      content:
          'Arista Valerius đứng trên đỉnh ngọn đồi nhìn xuống thung lũng sương mù...',
      isPinned: false,
      words: 13,
      date: '26/10',
    ),
  ];

  void _showAboutDialog() {
    showDialog(
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
            color: Colors.white.withOpacity(0.05),
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

  void _showGoalDialog() {
    final controller = TextEditingController(text: _dailyGoal.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Mục tiêu viết hàng ngày',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            suffixText: 'từ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              setState(() {
                _dailyGoal = int.tryParse(controller.text) ?? 500;
              });
              Navigator.pop(context);
            },
            child: Text('Lưu', style: TextStyle(color: widget.themeColor)),
          ),
        ],
      ),
    );
  }

  void _openEditor([Note? note]) async {
    final result = await Navigator.push<Note>(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(
          note: note,
          themeColor: widget.themeColor,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        final index = _notes.indexWhere((n) => n.id == result.id);
        if (index >= 0) {
          _notes[index] = result;
        } else {
          _notes.insert(0, result);
        }
        _sortNotes();
      });
    }
  }

  void _togglePin(String id) {
    setState(() {
      final index = _notes.indexWhere((n) => n.id == id);
      if (index >= 0) {
        _notes[index].isPinned = !_notes[index].isPinned;
        _sortNotes();
      }
    });
  }

  void _sortNotes() {
    _notes.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _notes.where((n) {
      final q = _searchQuery.toLowerCase();
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q);
    }).toList();

    final totalWords = _notes.fold<int>(0, (sum, n) => sum + n.words);
    final progress = (totalWords / _dailyGoal).clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          // QUẦNG SÁNG RADIAL GRADIENT MỜ MỊN LAN TỎA
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
                    widget.themeColor.withOpacity(0.45),
                    widget.themeColor.withOpacity(0.15),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                              icon: Icon(Icons.bolt,
                                  color: widget.themeColor, size: 20),
                              onPressed: _showAboutDialog,
                            ),
                            IconButton(
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.star_outline,
                                  color: Colors.amber, size: 20),
                              onPressed: () {
                                final colors = [
                                  const Color(0xFFEF4444),
                                  const Color(0xFF3B82F6),
                                  const Color(0xFF10B981),
                                  const Color(0xFFA855F7),
                                ];
                                final nextIndex = (colors.indexOf(
                                            widget.themeColor) +
                                        1) %
                                    colors.length;
                                widget.onThemeChanged(colors[nextIndex]);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showGoalDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('chào mừng đã đến với app',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                                const SizedBox(height: 2),
                                Text(
                                    'Mục tiêu: $totalWords / $_dailyGoal từ',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white70)),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      widget.themeColor),
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
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white12),
                        ),
                        child: IconButton(
                          icon: Icon(
                              _isGridMode
                                  ? Icons.grid_view
                                  : Icons.view_agenda,
                              size: 18),
                          onPressed: () {
                            setState(() {
                              _isGridMode = !_isGridMode;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm bài viết...',
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredNotes.isEmpty
                        ? const Center(
                            child: Text('Chưa có bài viết nào',
                                style: TextStyle(color: Colors.white38)),
                          )
                        : _isGridMode
                            ? GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 1.1,
                                ),
                                itemCount: filteredNotes.length,
                                itemBuilder: (context, index) {
                                  return _buildNoteCard(
                                      filteredNotes[index]);
                                },
                              )
                            : ListView.builder(
                                itemCount: filteredNotes.length,
                                itemBuilder: (context, index) {
                                  return _buildNoteCard(
                                      filteredNotes[index]);
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.themeColor,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
        onPressed: () => _openEditor(),
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return GestureDetector(
      onTap: () => _openEditor(note),
      child: Container(
        margin: EdgeInsets.only(bottom: _isGridMode ? 0 : 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: note.isPinned
                  ? widget.themeColor.withOpacity(0.5)
                  : Colors.white10),
        ),
        child: Column(
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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
            Expanded(
              child: Text(
                note.content,
                maxLines: _isGridMode ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${note.words} từ',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                Text(note.date,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= MÀN HÌNH SOẠN THẢO VĂN BẢN (EDITOR) =================
class EditorScreen extends StatefulWidget {
  final Note? note;
  final Color themeColor;

  const EditorScreen({
    super.key,
    this.note,
    required this.themeColor,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _calculateWords();

    _contentController.addListener(_calculateWords);
  }

  void _calculateWords() {
    final text = _contentController.text.trim();
    setState(() {
      _wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    });
  }

  void _saveAndExit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}';

    final noteToSave = Note(
      id: widget.note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.isEmpty ? 'Bài viết mới' : title,
      content: content,
      isPinned: widget.note?.isPinned ?? false,
      words: _wordCount,
      date: dateStr,
    );

    Navigator.pop(context, noteToSave);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: _saveAndExit,
        ),
        actions: [
          IconButton(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withOpacity(0.2),
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
                  style: const TextStyle(
                      fontSize: 16, color: Colors.white90, height: 1.6),
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
    );
  }
}
