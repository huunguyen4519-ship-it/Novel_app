import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppSettings(),
      child: const NovelApp(),
    ),
  );
}

// ================= QUẢN LÝ THIẾT LẬP GIAO DIỆN & LOANG MÀU =================
class AppSettings extends ChangeNotifier {
  Color _themeColor = const Color(0xFFEF4444); // Ruby Red mặc định
  bool _isGridMode = true;
  int _dailyGoal = 500;
  bool _isSerifFont = false;

  Color get themeColor => _themeColor;
  bool get isGridMode => _isGridMode;
  int get dailyGoal => _dailyGoal;
  bool get isSerifFont => _isSerifFont;

  void setThemeColor(Color color) {
    _themeColor = color;
    notifyListeners();
  }

  void toggleGridMode() {
    _isGridMode = !_isGridMode;
    notifyListeners();
  }

  void setDailyGoal(int goal) {
    _dailyGoal = goal;
    notifyListeners();
  }

  void toggleFont() {
    _isSerifFont = !_isSerifFont;
    notifyListeners();
  }
}

// ================= MÔ HÌNH BÀI VIẾT =================
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
class NovelApp extends StatelessWidget {
  const NovelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    return MaterialApp(
      title: 'Novel App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08080A),
        primaryColor: settings.themeColor,
        colorScheme: ColorScheme.dark(primary: settings.themeColor),
      ),
      home: const HomeScreen(),
    );
  }
}

// ================= MÀN HÌNH CHÍNH =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Note> _notes = [
    Note(
      id: '1',
      title: 'Ý tưởng tiểu thuyết mới',
      content: 'Chào mừng bạn đến với ứng dụng Novel App! Nhấn vào biểu tượng logo để xem thông tin hoặc nhấn vào ngôi sao để đổi giao diện.',
      isPinned: true,
      words: 32,
      date: '27-10',
    ),
    Note(
      id: '2',
      title: 'Con đường của ánh sáng - Chương 1',
      content: 'Arista Valerius đứng trên đỉnh ngọn đồi nhìn xuống thung lũng sương mù...',
      isPinned: false,
      words: 150,
      date: '26-10',
    ),
  ];

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Azrael Novel App', style: TextStyle(fontSize: 18, color: Colors.white)),
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
            style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Trải nghiệm ngay', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showGoalDialog() {
    final settings = Provider.of<AppSettings>(context, listen: false);
    final controller = TextEditingController(text: settings.dailyGoal.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Mục tiêu viết hàng ngày', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            suffixText: 'từ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              final newGoal = int.tryParse(controller.text) ?? 500;
              settings.setDailyGoal(newGoal);
              Navigator.pop(context);
            },
            child: const Text('Lưu', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    final totalWords = _notes.fold<int>(0, (sum, n) => sum + n.words);
    final progress = (totalWords / settings.dailyGoal).clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          // LOANG MÀU NỀN DYNAMIC (AMBIENT GLOW)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: settings.themeColor.withOpacity(0.35),
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // HEADER BAR
                  Row(
                    children: [
                      // LOGO & STAR
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
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.bolt, color: Colors.redAccent, size: 20),
                              onPressed: _showAboutDialog,
                            ),
                            IconButton(
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.star_outline, color: Colors.amber, size: 20),
                              onPressed: () {
                                // Mở menu đổi màu
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // THẺ MỤC TIÊU VIẾT
                      Expanded(
                        child: GestureDetector(
                          onTap: _showGoalDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('chào mừng đã đến với app', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 2),
                                Text('Mục tiêu: $totalWords / ${settings.dailyGoal} từ', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(settings.themeColor),
                                  minHeight: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // DỌC / NGANG LAYOUT TOGGLE
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white12),
                        ),
                        child: IconButton(
                          icon: Icon(settings.isGridMode ? Icons.grid_view : Icons.view_agenda, size: 18),
                          onPressed: settings.toggleGridMode,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // SEARCH BAR
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm bài viết...',
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // DANH SÁCH BÀI VIẾT
                  Expanded(
                    child: ListView.builder(
                      itemCount: _notes.length,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (note.isPinned) const Icon(Icons.push_pin, size: 14, color: Colors.amber),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(note.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                            ],
                          ),
                        );
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
        backgroundColor: settings.themeColor,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
        onPressed: () {},
      ),
    );
  }
}
