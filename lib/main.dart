import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const NovelApp());
}

class NovelApp extends StatelessWidget {
  const NovelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Novel App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final TextEditingController _textController = TextEditingController();
  final UndoHistoryController _undoController = UndoHistoryController();

  int _wordCount = 0;
  int _wordGoal = 500; // Mục tiêu số từ
  bool _hasWarned = false; // Đảm bảo chỉ cảnh báo 1 lần
  int _streakDays = 5; // Điểm danh chuỗi (ví dụ mặc định là 5 ngày)

  // Danh sách các màu nền loang (Gradient) đẹp
  final List<LinearGradient> _gradients = [
    const LinearGradient(
      colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFF4CA1AF), Color(0xFFC4E0E5)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    const LinearGradient(
      colors: [Color(0xFFff9966), Color(0xFFff5e62)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  int _currentGradientIndex = 0;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  // Hàm xử lý khi gõ chữ
  void _onTextChanged() {
    String text = _textController.text;
    
    // Thuật toán đếm từ chuẩn (tách theo khoảng trắng và xuống dòng)
    int currentCount = text.trim().isEmpty 
        ? 0 
        : text.trim().split(RegExp(r'\s+')).length;

    if (currentCount != _wordCount) {
      setState(() {
        _wordCount = currentCount;
      });

      // Lời nhắc nghỉ ngơi khi vượt mục tiêu
      if (_wordCount > _wordGoal && !_hasWarned) {
        _hasWarned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bạn đã viết quá giới hạn từ mục tiêu. Hãy nghỉ ngơi để bảo vệ mắt nhé! 🌿'),
              backgroundColor: Colors.teal,
              duration: Duration(seconds: 4),
            ),
          );
        });
      }
    }
  }

  // Hàm chèn định dạng văn bản (Markdown) vào vị trí con trỏ
  void _insertFormatting(String prefix, String suffix) {
    final text = _textController.text;
    final selection = _textController.selection;

    if (selection.start == -1 || selection.end == -1) {
      // Nếu không bôi đen, chèn vào cuối văn bản
      _textController.text = text + prefix + suffix;
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length - suffix.length);
      return;
    }

    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(selection.start, selection.end, '$prefix$selectedText$suffix');

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + prefix.length + selectedText.length),
    );
  }

  // Hiển thị Menu khi bấm nút Ngôi Sao
  void _showStarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        '🌟 Menu Tùy Chỉnh',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 30),

                    // 1. Điểm danh chuỗi
                    ListTile(
                      leading: const Icon(Icons.local_fire_department, color: Colors.orange, size: 30),
                      title: const Text('Chuỗi viết lách (Streak)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Bạn đã viết liên tục $_streakDays ngày!'),
                      trailing: ElevatedButton(
                        onPressed: () {
                          setModalState(() {
                            _streakDays++;
                          });
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Điểm danh thành công!')),
                          );
                          Navigator.pop(context);
                        },
                        child: const Text('Điểm danh'),
                      ),
                    ),
                    const Divider(),

                    // 2. Chỉnh giao diện nền
                    const Text('🎨 Tùy chỉnh màu nền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(_gradients.length, (index) {
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _currentGradientIndex = index;
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: _gradients[index],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _currentGradientIndex == index ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                          ),
                        );
                      }),
                    ),
                    const Divider(height: 30),

                    // 3. Tùy chỉnh xuất file
                    const Text('📄 Xuất tệp tin (Sao chép)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.description, size: 16),
                          label: const Text('.TXT'),
                          onPressed: () => _exportText('txt'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.code, size: 16),
                          label: const Text('.MD'),
                          onPressed: () => _exportText('md'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.picture_as_pdf, size: 16),
                          label: const Text('.DOCX / .PDF'),
                          onPressed: () => _exportText('docx'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  // Hàm xử lý xuất file (Sử dụng Clipboard để giữ app thuần Flutter, dễ build)
  void _exportText(String format) {
    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Văn bản trống, không có gì để xuất!')),
      );
      return;
    }
    
    Clipboard.setData(ClipboardData(text: _textController.text));
    Navigator.pop(context); // Đóng menu
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép nội dung định dạng $format vào khay nhớ tạm! Bạn có thể dán vào tệp của mình.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Viết Truyện', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Nút ngôi sao bắt buộc
          IconButton(
            icon: const Icon(Icons.star, color: Colors.yellow, size: 30),
            onPressed: _showStarMenu,
            tooltip: 'Menu Tùy Chỉnh',
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Container(
        // Màu nền loang đẹp
        decoration: BoxDecoration(
          gradient: _gradients[_currentGradientIndex],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Thanh công cụ Editor (In nghiêng, gạch chân, H1, H2, Undo, v.v...)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.undo),
                        onPressed: () => _undoController.undo(),
                        tooltip: 'Hoàn tác (Undo)',
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo),
                        onPressed: () => _undoController.redo(),
                        tooltip: 'Làm lại (Redo)',
                      ),
                      const VerticalDivider(width: 1, color: Colors.grey),
                      IconButton(
                        icon: const Text('H1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        onPressed: () => _insertFormatting('# ', ''),
                      ),
                      IconButton(
                        icon: const Text('H2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        onPressed: () => _insertFormatting('## ', ''),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_bold),
                        onPressed: () => _insertFormatting('**', '**'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_italic),
                        onPressed: () => _insertFormatting('*', '*'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_underline),
                        onPressed: () => _insertFormatting('<u>', '</u>'),
                      ),
                    ],
                  ),
                ),
              ),

              // Vùng viết văn bản
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
                    ],
                  ),
                  child: TextField(
                    controller: _textController,
                    undoController: _undoController,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: 'Bắt đầu viết câu chuyện của bạn tại đây...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              // Thanh trạng thái (Bộ đếm từ)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Từ: $_wordCount / $_wordGoal',
                      style: TextStyle(
                        color: _wordCount > _wordGoal ? Colors.redAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '🔥 Streak: $_streakDays',
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
