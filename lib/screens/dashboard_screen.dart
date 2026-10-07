import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'editor_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dữ liệu mẫu khởi tạo cho The Radiant Path
    final List<Map<String, dynamic>> dummyCards = [
      {"title": "Chương 1: Tàn Tích", "synopsis": "azrael tỉnh dậy giữa đống đổ nát, không ký ức...", "color": 0xFF282121},
      {"title": "Lore: Ánh Sáng Tàn Dư", "synopsis": "Hệ thống ma pháp ngầm, kích hoạt qua đồng tử.", "color": 0xFF3D1E1E},
      {"title": "Chương 2: Lưỡi Gươm", "synopsis": "Chạm trán sinh vật bóng tối tại Rừng Đen.", "color": 0xFF282121},
      {"title": "Ý tưởng: Nút thắt Vol 1", "synopsis": "Phát hiện ra sự thật về viên đá linh hồn.", "color": 0xFF2D251E},
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Thanh tìm kiếm nổi (Floating Search Bar)
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF282121),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm chương, nhân vật, lore...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Con Đường Của Ánh Sáng", 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF8B3A3A))
              ),
              const SizedBox(height: 16),
              // Lưới thẻ bài mượt mà
              Expanded(
                child: MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  itemCount: dummyCards.length,
                  itemBuilder: (context, index) {
                    final item = dummyCards[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => EditorScreen(title: item['title'])),
                        );
                      },
                      child: Card(
                        color: Color(item['color']),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'],
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.4),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item['synopsis'],
                                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7), height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditorScreen(title: "Chương mới")),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 4,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}
