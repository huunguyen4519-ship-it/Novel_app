import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorScreen extends StatefulWidget {
  final String title;
  const EditorScreen({super.key, required this.title});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final TextEditingController _contentController = TextEditingController();

  // Đóng gói ngữ cảnh dán thẳng cho Gemini
  void _packForGemini() {
    String contextPackage = '''
========================================
[TÁC PHẨM]: The Radiant Path
[BỐI CẢNH & CHƯƠNG]: ${widget.title}
[NỘI DUNG ĐANG VIẾT DỞ]:
${_contentController.text.isNotEmpty ? _contentController.text : "(Chưa có nội dung)"}

[YÊU CẦU DÀNH CHO GEMINI]:
Giữ nguyên văn phong dark fantasy u tối. Hãy giúp tớ...
========================================
''';
    
    Clipboard.setData(ClipboardData(text: contextPackage)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Đã đóng gói! Chủ nhân hãy dán ngữ cảnh này cho em nhé.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF8B3A3A), // Đỏ sẫm
        ),
      );
    });
  }

  // Chèn nhanh ký tự từ thanh Accessory
  void _insertText(String text) {
    final int cursorPos = _contentController.selection.base.offset;
    if (cursorPos >= 0) {
      String currentText = _contentController.text;
      String newText = currentText.substring(0, cursorPos) + text + currentText.substring(cursorPos);
      _contentController.value = _contentController.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: cursorPos + text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontSize: 18, 
                  height: 1.8, // Khoảng cách dòng chuẩn sách
                  color: Color(0xFFEAEAEA),
                ),
                decoration: const InputDecoration(
                  hintText: 'Bắt đầu chương mới tại đây...',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          // Thanh Phím Tắt Phụ Trợ (Keyboard Accessory Bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1A1A),
              border: Border(top: BorderSide(color: Color(0xFF282121), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Text('@', style: TextStyle(fontSize: 22, color: Colors.white54)),
                      onPressed: () => _insertText('@'), // Gọi nhân vật
                    ),
                    IconButton(
                      icon: const Text('[[', style: TextStyle(fontSize: 18, color: Colors.white54)),
                      onPressed: () => _insertText('[[]]'), // Gọi Lore
                    ),
                    IconButton(
                      icon: const Text('“ ”', style: TextStyle(fontSize: 18, color: Colors.white54)),
                      onPressed: () => _insertText('“”'), // Thoại
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _packForGemini,
                  icon: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                  label: const Text('Gửi Gemini', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
