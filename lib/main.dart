import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Gộp các phần của 13 file Dart thành một main.dart độc lập.

// ===== Nội dung gốc: lib/main.dart =====

void main() {
  runApp(const NovelApp());
}

class NovelApp extends StatefulWidget {
  const NovelApp({super.key});

  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  final NoteStore _store = NoteStore(NoteStorage());
  late final Future<void> _boot = _bootApp();

  /// Nạp dữ liệu và giữ màn loading tối thiểu 1.1 giây cho mượt.
  Future<void> _bootApp() async {
    await Future.wait<void>([
      _store.load(),
      Future<void>.delayed(const Duration(milliseconds: 1100)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final color = _store.themeColor;
        return MaterialApp(
          title: 'Novel App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: kBgColor,
            primaryColor: color,
            colorScheme: ColorScheme.dark(primary: color),
          ),
          home: FutureBuilder<void>(
            future: _boot,
            builder: (context, snapshot) {
              final ready = snapshot.connectionState == ConnectionState.done;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOut,
                child: ready
                    ? HomeScreen(key: const ValueKey('home'), store: _store)
                    : LoadingScreen(
                        key: const ValueKey('loading'),
                        themeColor: color,
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

// ===== Nội dung gốc: lib/core/app_theme.dart =====

const List<Color> kThemeColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFA855F7),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

const Color kWhite90 = Color(0xE6FFFFFF);
const Color kBgColor = Color(0xFF08080A);
const Color kSheetColor = Color(0xFF16161C);

extension ColorFade on Color {
  /// Trả về màu này với độ đục [opacity] (0.0 - 1.0).
  Color fade(double opacity) =>
      withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

RoundedRectangleBorder dialogShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));

/// Chuyển màn mượt: trượt nhẹ kèm mờ dần.
PageRouteBuilder<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Nền loang mềm theo màu chủ đề.
class SoftBackground extends StatelessWidget {
  const SoftBackground({super.key, required this.themeColor});

  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(themeColor);
    final accent = hsl.withHue((hsl.hue + 40) % 360).toColor();

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(top: -160, left: -120, child: _blob(themeColor, 420)),
            Positioned(top: -80, right: -160, child: _blob(accent, 360)),
            Positioned(
              bottom: -200,
              left: -100,
              child: _blob(themeColor.fade(0.7), 320),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    kBgColor.fade(0.4),
                    kBgColor.fade(0.85),
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

/// Thu nhỏ nhẹ khi nhấn, tạo cảm giác phản hồi mượt.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: () {
        _set(false);
        widget.onLongPress?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ===== Nội dung gốc: lib/models/note.dart =====

const int kTrashDays = 30;
const int kDefaultGoal = 500;
const Duration kRestoreBadgeDuration = Duration(days: 1);

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

/// HÀM ĐẾM TỪ DUY NHẤT của cả app. Mọi nơi đều dùng hàm này để số luôn khớp.
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

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    this.isPinned = false,
    required this.updatedAt,
    this.deletedAt,
    this.trashGroupId,
    this.restoredAt,
    this.goalTarget = kDefaultGoal,
    this.groupId,
    this.isGroupHead = false,
    this.order = 0,
  }) : words = countWords(content);

  final String id;
  final String title;
  final String content;
  final bool isPinned;
  final DateTime updatedAt;

  /// Thời điểm bị xóa (null = đang dùng bình thường).
  final DateTime? deletedAt;

  /// Mã đợt xóa. Các bài xóa cùng nhóm có chung mã để khôi phục cùng nhau.
  final String? trashGroupId;

  /// Thời điểm khôi phục từ thùng rác (icon tái chế hiện trong 1 ngày).
  final DateTime? restoredAt;

  /// Chỉ tiêu riêng của thẻ độc lập.
  final int goalTarget;

  /// Id của thẻ dẫn đầu mà bài này thuộc về (null = không thuộc nhóm).
  final String? groupId;

  /// Thẻ dẫn đầu nhóm chương.
  final bool isGroupHead;

  /// Thứ tự chương trong nhóm.
  final int order;

  /// Số từ, luôn tính từ nội dung.
  final int words;

  bool get isStandalone => groupId == null && !isGroupHead;

  String get displayTitle => title.trim().isEmpty ? 'Không có tiêu đề' : title;

  bool get showRecycleBadge {
    final restored = restoredAt;
    if (restored == null) return false;
    return DateTime.now().difference(restored) < kRestoreBadgeDuration;
  }

  Note copyWith({
    String? title,
    String? content,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeleted = false,
    String? trashGroupId,
    bool clearTrashGroup = false,
    DateTime? restoredAt,
    int? goalTarget,
    String? groupId,
    bool clearGroup = false,
    bool? isGroupHead,
    int? order,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      isPinned: isPinned ?? this.isPinned,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      trashGroupId:
          clearTrashGroup ? null : (trashGroupId ?? this.trashGroupId),
      restoredAt: restoredAt ?? this.restoredAt,
      goalTarget: goalTarget ?? this.goalTarget,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      isGroupHead: isGroupHead ?? this.isGroupHead,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'pinned': isPinned,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'trashGroupId': trashGroupId,
        'restoredAt': restoredAt?.toIso8601String(),
        'goalTarget': goalTarget,
        'groupId': groupId,
        'isGroupHead': isGroupHead,
        'order': order,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      isPinned: (json['pinned'] as bool?) ?? false,
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
      deletedAt: _parseDate(json['deletedAt']),
      trashGroupId: json['trashGroupId'] as String?,
      restoredAt: _parseDate(json['restoredAt']),
      goalTarget: (json['goalTarget'] as int?) ?? kDefaultGoal,
      groupId: json['groupId'] as String?,
      isGroupHead: (json['isGroupHead'] as bool?) ?? false,
      order: (json['order'] as int?) ?? 0,
    );
  }
}

/// Số ngày còn lại trước khi bài trong thùng rác bị xóa vĩnh viễn.
int trashDaysLeft(Note note) {
  final deleted = note.deletedAt;
  if (deleted == null) return kTrashDays;
  final left = kTrashDays - DateTime.now().difference(deleted).inDays;
  return left < 0 ? 0 : left;
}

bool isTrashExpired(Note note) {
  final deleted = note.deletedAt;
  if (deleted == null) return false;
  return DateTime.now().difference(deleted) >=
      const Duration(days: kTrashDays);
}

// ===== Nội dung gốc: lib/data/note_storage.dart =====

class StoredState {
  const StoredState({
    this.notes,
    this.trash = const [],
    this.goalNoteId,
    this.streakDays = 0,
    this.lastStreakDate,
    this.themeValue,
    this.legacyGoalTarget,
  });

  /// null = lần đầu mở app, cần tạo bài mẫu.
  final List<Note>? notes;
  final List<Note> trash;
  final String? goalNoteId;
  final int streakDays;
  final DateTime? lastStreakDate;
  final int? themeValue;

  /// Chỉ tiêu dùng chung cũ, sẽ được gán cho thẻ mục tiêu khi nâng cấp.
  final int? legacyGoalTarget;
}

class NoteStorage {
  Future<StoredState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawNotes = prefs.getString('notes');
    final rawTrash = prefs.getString('trash');
    final lastRaw = prefs.getString('lastStreak');
    return StoredState(
      notes: rawNotes == null ? null : _decode(rawNotes),
      trash: rawTrash == null ? const [] : _decode(rawTrash),
      goalNoteId: prefs.getString('goalNoteId'),
      streakDays: prefs.getInt('streakDays') ?? 0,
      lastStreakDate: lastRaw == null ? null : DateTime.tryParse(lastRaw),
      themeValue: prefs.getInt('theme'),
      legacyGoalTarget: prefs.getInt('goalTarget'),
    );
  }

  Future<void> save({
    required List<Note> notes,
    required List<Note> trash,
    required String? goalNoteId,
    required int streakDays,
    required DateTime? lastStreakDate,
    required int themeValue,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'notes', jsonEncode(notes.map((n) => n.toJson()).toList()));
    await prefs.setString(
        'trash', jsonEncode(trash.map((n) => n.toJson()).toList()));
    if (goalNoteId == null) {
      await prefs.remove('goalNoteId');
    } else {
      await prefs.setString('goalNoteId', goalNoteId);
    }
    await prefs.setInt('streakDays', streakDays);
    if (lastStreakDate == null) {
      await prefs.remove('lastStreak');
    } else {
      await prefs.setString('lastStreak', lastStreakDate.toIso8601String());
    }
    await prefs.setInt('theme', themeValue);
    // Dọn khóa cũ sau khi đã chuyển sang chỉ tiêu theo từng thẻ.
    await prefs.remove('goalTarget');
  }

  List<Note> _decode(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

List<Note> sampleNotes() {
  final now = DateTime.now();
  const welcome =
      'Chào mừng bạn đến với ứng dụng Novel App! Nhấn nút cộng ở góc dưới để '
      'tạo bài viết mới hoặc nhấn vào bài này để chỉnh sửa. Nhấn giữ một bài '
      'để đặt làm mục tiêu, đặt làm nhóm chương hoặc xóa. Nhấn vào ngôi sao '
      'ở góc trên để tùy chỉnh giao diện, xuất file, mở thùng rác và xem chuỗi '
      'ngày viết liên tục.';
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

// ===== Nội dung gốc: lib/store/note_store.dart =====

/// Nguồn dữ liệu duy nhất của app. Mọi màn đọc và ghi qua đây.
class NoteStore extends ChangeNotifier {
  NoteStore(this._storage);

  final NoteStorage _storage;
  final List<Note> _notes = [];
  final List<Note> _trash = [];
  String? _goalNoteId;
  int _streakDays = 0;
  DateTime? _lastStreakDate;
  Color _themeColor = kThemeColors.first;
  bool _loaded = false;

  bool get loaded => _loaded;
  Color get themeColor => _themeColor;
  int get streakDays => _streakDays;
  DateTime? get lastStreakDate => _lastStreakDate;
  String? get goalNoteId => _goalNoteId;

  // ---------- Truy vấn ----------

  Note? findNote(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Các thẻ hiển thị ở màn chính: thẻ độc lập và thẻ dẫn đầu.
  List<Note> get homeNotes {
    final list = _notes.where((n) => n.groupId == null).toList();
    list.sort(_compare);
    return list;
  }

  List<Note> get heads => homeNotes.where((n) => n.isGroupHead).toList();

  List<Note> chaptersOf(String headId) {
    final list = _notes.where((n) => n.groupId == headId).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  int nextOrder(String headId) {
    final chapters = chaptersOf(headId);
    return chapters.isEmpty ? 0 : chapters.last.order + 1;
  }

  int groupWordCount(String headId) {
    var total = findNote(headId)?.words ?? 0;
    for (final c in chaptersOf(headId)) {
      total += c.words;
    }
    return total;
  }

  Note? get goalNote => _goalNoteId == null ? null : findNote(_goalNoteId!);

  int get goalTarget => goalNote?.goalTarget ?? kDefaultGoal;

  /// Thùng rác gom theo đợt xóa. Mỗi phần tử là một danh sách bài.
  List<List<Note>> get trashEntries {
    final entries = <List<Note>>[];
    final byKey = <String, List<Note>>{};
    for (final n in _trash) {
      final key = n.trashGroupId;
      if (key == null) {
        entries.add([n]);
      } else {
        final existing = byKey[key];
        if (existing != null) {
          existing.add(n);
        } else {
          final created = [n];
          byKey[key] = created;
          entries.add(created);
        }
      }
    }
    return entries;
  }

  int get trashCount => trashEntries.length;

  /// Bài đại diện của một đợt xóa (thẻ dẫn đầu nếu có).
  Note primaryOf(List<Note> entry) {
    for (final n in entry) {
      if (n.isGroupHead) return n;
    }
    return entry.first;
  }

  static int _compare(Note a, Note b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final byDate = b.updatedAt.compareTo(a.updatedAt);
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  }

  // ---------- Tải dữ liệu ----------

  Future<void> load() async {
    try {
      final s = await _storage.load();
      _notes
        ..clear()
        ..addAll(s.notes ?? sampleNotes());
      _trash
        ..clear()
        ..addAll(s.trash);
      _goalNoteId = s.goalNoteId;
      _streakDays = s.streakDays;
      _lastStreakDate = s.lastStreakDate;
      if (s.themeValue != null) _themeColor = Color(s.themeValue!);
      final legacy = s.legacyGoalTarget;
      final goal = goalNote;
      if (legacy != null && goal != null) {
        _put(goal.copyWith(goalTarget: legacy));
      }
    } catch (_) {
      if (_notes.isEmpty) _notes.addAll(sampleNotes());
    }
    _trash.removeWhere(isTrashExpired);
    _normalize();
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  // ---------- Mục tiêu và chỉ tiêu ----------

  void setGoal(String id) {
    final n = findNote(id);
    if (n == null || !n.isStandalone) return;
    _goalNoteId = id;
    _commit();
  }

  /// Chỉ tiêu được lưu riêng cho từng thẻ mục tiêu.
  void setGoalTarget(int target) {
    final goal = goalNote;
    if (goal == null) return;
    _put(goal.copyWith(goalTarget: target));
    _commit();
  }

  void setTheme(Color color) {
    _themeColor = color;
    _commit();
  }

  // ---------- Bài viết ----------

  void togglePin(String id) {
    final n = findNote(id);
    if (n == null) return;
    _put(n.copyWith(isPinned: !n.isPinned));
    _commit();
  }

  Note createNote({
    required String title,
    required String content,
    String? groupId,
  }) {
    final now = DateTime.now();
    final note = Note(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      updatedAt: now,
      groupId: groupId,
      order: groupId == null ? 0 : nextOrder(groupId),
    );
    _notes.add(note);
    if (note.words > 0) _recordStreak(now);
    _commit();
    return note;
  }

  void updateNote(String id, {required String title, required String content}) {
    final old = findNote(id);
    if (old == null) return;
    if (old.title == title && old.content == content) return;
    final now = DateTime.now();
    final updated =
        old.copyWith(title: title, content: content, updatedAt: now);
    if (updated.words > old.words) _recordStreak(now);
    _put(updated);
    _commit();
  }

  void renameGroup(String headId, String name) {
    final head = findNote(headId);
    if (head == null) return;
    updateNote(headId, title: name, content: head.content);
  }

  // ---------- Nhóm chương ----------

  void makeGroupHead(String id) {
    final n = findNote(id);
    if (n == null || !n.isStandalone) return;
    _put(n.copyWith(isGroupHead: true));
    _commit();
  }

  void assignToGroup(String noteId, String headId) {
    final note = findNote(noteId);
    final head = findNote(headId);
    if (note == null || head == null || noteId == headId) return;
    if (!note.isStandalone || !head.isGroupHead) return;
    _put(note.copyWith(
      groupId: headId,
      isGroupHead: false,
      order: nextOrder(headId),
    ));
    _commit();
  }

  void removeFromGroup(String chapterId) {
    final n = findNote(chapterId);
    if (n == null || n.groupId == null) return;
    _put(n.copyWith(clearGroup: true, order: 0));
    _commit();
  }

  void reorderChapters(String headId, List<String> orderedIds) {
    for (var i = 0; i < orderedIds.length; i++) {
      final n = findNote(orderedIds[i]);
      if (n != null) _put(n.copyWith(order: i));
    }
    _commit();
  }

  // ---------- Xóa và thùng rác ----------

  /// Xóa một thẻ độc lập hoặc một chương (đưa vào thùng rác, xóa riêng lẻ).
  void moveToTrash(String id) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final note = _notes.removeAt(i);
    if (_goalNoteId == id) _goalNoteId = null;
    _trash.insert(
      0,
      note.copyWith(
        deletedAt: DateTime.now(),
        clearTrashGroup: true,
        isGroupHead: false,
      ),
    );
    _commit();
  }

  /// Xóa cả nhóm: thẻ dẫn đầu và mọi chương cùng một đợt xóa.
  void trashGroup(String headId) {
    final head = findNote(headId);
    if (head == null) return;
    final now = DateTime.now();
    final key = now.microsecondsSinceEpoch.toString();
    final members = _notes
        .where((n) => n.id == headId || n.groupId == headId)
        .toList();
    _notes.removeWhere((n) => n.id == headId || n.groupId == headId);
    for (final m in members) {
      _trash.insert(0, m.copyWith(deletedAt: now, trashGroupId: key));
    }
    if (_goalNoteId != null && members.any((m) => m.id == _goalNoteId)) {
      _goalNoteId = null;
    }
    _commit();
  }

  /// Xóa chỉ thẻ dẫn đầu. Chương được chọn sẽ thành thẻ dẫn đầu mới.
  void deleteHeadOnly(String headId, {String? newHeadId}) {
    final head = findNote(headId);
    if (head == null) return;
    final now = DateTime.now();
    if (newHeadId != null) {
      final idx = _notes.indexWhere((n) => n.id == newHeadId);
      if (idx >= 0 && _notes[idx].groupId == headId) {
        _notes[idx] = _notes[idx].copyWith(
          clearGroup: true,
          isGroupHead: true,
          order: 0,
        );
        for (final c in chaptersOf(headId)) {
          if (c.id != newHeadId) {
            _put(c.copyWith(groupId: newHeadId));
          }
        }
      }
    }
    _notes.removeWhere((n) => n.id == headId);
    _trash.insert(
      0,
      head.copyWith(
        deletedAt: now,
        clearTrashGroup: true,
        clearGroup: true,
        isGroupHead: false,
      ),
    );
    if (_goalNoteId == headId) _goalNoteId = null;
    _commit();
  }

  /// Khôi phục một đợt xóa. Đợt có thẻ dẫn đầu thì khôi phục cả nhóm.
  /// Mọi bài được khôi phục đều có dấu tái chế trong 1 ngày.
  void restoreEntry(Note primary) {
    final now = DateTime.now();
    final key = primary.trashGroupId;
    if (key != null) {
      final members = _trash.where((n) => n.trashGroupId == key).toList();
      _trash.removeWhere((n) => n.trashGroupId == key);
      for (final m in members) {
        _notes.add(m.copyWith(
          clearDeleted: true,
          clearTrashGroup: true,
          restoredAt: now,
        ));
      }
    } else {
      final i = _trash.indexWhere((n) => n.id == primary.id);
      if (i < 0) return;
      final note = _trash.removeAt(i);
      _notes.add(note.copyWith(
        clearDeleted: true,
        restoredAt: now,
        isGroupHead: false,
      ));
    }
    _commit();
  }

  void deleteForeverEntry(Note primary) {
    final key = primary.trashGroupId;
    if (key != null) {
      _trash.removeWhere((n) => n.trashGroupId == key);
    } else {
      _trash.removeWhere((n) => n.id == primary.id);
    }
    _commit();
  }

  void emptyTrash() {
    _trash.clear();
    _commit();
  }

  void purgeExpired() {
    final before = _trash.length;
    _trash.removeWhere(isTrashExpired);
    if (_trash.length != before) _commit();
  }

  // ---------- Nội bộ ----------

  void _recordStreak(DateTime now) {
    final today = dateOnly(now);
    final last = _lastStreakDate;
    if (last == null) {
      _streakDays = 1;
    } else {
      final lastDay = dateOnly(last);
      if (lastDay == today) {
        // đã tính hôm nay rồi
      } else if (lastDay == today.subtract(const Duration(days: 1))) {
        _streakDays += 1;
      } else {
        _streakDays = 1;
      }
    }
    _lastStreakDate = today;
  }

  void _put(Note n) {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i >= 0) _notes[i] = n;
  }

  /// Sửa các liên kết hỏng: chương trỏ tới nhóm không tồn tại thành thẻ độc lập.
  void _normalize() {
    final headIds = <String>{
      for (final n in _notes)
        if (n.isGroupHead && n.groupId == null) n.id,
    };
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      if (n.groupId != null && !headIds.contains(n.groupId)) {
        _notes[i] = n.copyWith(clearGroup: true, order: 0);
      } else if (n.isGroupHead && n.groupId != null) {
        _notes[i] = n.copyWith(isGroupHead: false);
      }
    }
    final goal = goalNote;
    if (goal == null || !goal.isStandalone) _goalNoteId = null;
  }

  void _commit() {
    _normalize();
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _storage.save(
        notes: List<Note>.of(_notes),
        trash: List<Note>.of(_trash),
        goalNoteId: _goalNoteId,
        streakDays: _streakDays,
        lastStreakDate: _lastStreakDate,
        themeValue: _themeColor.value,
      );
    } catch (_) {}
  }
}

// ===== Nội dung gốc: lib/widgets/actions.dart =====

class SheetItem {
  const SheetItem({
    this.icon,
    this.iconColor,
    this.leadingText,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final Color? iconColor;
  final String? leadingText;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

// ---------- Hộp thoại chung ----------

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Color confirmColor = Colors.redAccent,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: Text(message,
          style: const TextStyle(color: Colors.white70, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  String? suffix,
  TextInputType keyboard = TextInputType.text,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(
      title: title,
      initial: initial,
      hint: hint,
      suffix: suffix,
      keyboard: keyboard,
    ),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.suffix,
    required this.keyboard,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? suffix;
  final TextInputType keyboard;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
      title: Text(widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Colors.white38),
          suffixText: widget.suffix,
          suffixStyle: const TextStyle(color: Colors.white54),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text('Lưu',
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ),
      ],
    );
  }
}

Future<Note?> pickNoteDialog(
  BuildContext context, {
  required String title,
  required List<Note> items,
}) {
  return showDialog<Note>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: items.isEmpty
            ? const Center(
                child: Text('Không có mục nào.',
                    style: TextStyle(color: Colors.white38)))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white10, height: 1),
                itemBuilder: (_, i) {
                  final n = items[i];
                  return ListTile(
                    dense: true,
                    title: Text(n.displayTitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${n.words} từ',
                        style: const TextStyle(color: Colors.white38)),
                    onTap: () => Navigator.pop(ctx, n),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );
}

void showRestReminder(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
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
        'thư giãn mắt.',
        style: TextStyle(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Đã hiểu',
              style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
        ),
      ],
    ),
  );
}

void showAppInfoDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
      title: Row(
        children: [
          Icon(Icons.bolt, color: Theme.of(ctx).colorScheme.primary),
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
          onPressed: () => Navigator.pop(ctx),
          child: Text('Trải nghiệm ngay',
              style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
        ),
      ],
    ),
  );
}

Future<void> showGoalDialog(BuildContext context, NoteStore store) async {
  final goal = store.goalNote;
  if (goal == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Nhấn giữ một thẻ để đặt làm mục tiêu.')),
    );
    return;
  }
  final text = await showInputDialog(
    context,
    title: 'Chỉ tiêu của "${goal.displayTitle}"',
    initial: store.goalTarget.toString(),
    suffix: 'từ',
    keyboard: TextInputType.number,
  );
  if (text == null) return;
  final value = int.tryParse(text);
  store.setGoalTarget(value == null || value <= 0 ? 1 : value);
}

// ---------- Menu nhấn giữ ----------

Future<void> _showSheet(
  BuildContext context, {
  required String title,
  required List<SheetItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: kSheetColor,
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
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 8),
            for (final item in items)
              ListTile(
                leading: item.leadingText != null
                    ? Text(item.leadingText!,
                        style: const TextStyle(fontSize: 26))
                    : Icon(item.icon ?? Icons.circle_outlined,
                        color: item.iconColor ?? Colors.white70),
                title: Text(item.label,
                    style: const TextStyle(fontSize: 13, color: Colors.white)),
                subtitle: item.subtitle == null
                    ? null
                    : Text(item.subtitle!,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  item.onTap();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Menu nhấn giữ thẻ độc lập.
Future<void> showNoteMenu(BuildContext context, NoteStore store, Note note) {
  final isGoal = store.goalNoteId == note.id;
  final hasHeads = store.heads.isNotEmpty;
  return _showSheet(
    context,
    title: note.displayTitle,
    items: [
      if (!isGoal)
        SheetItem(
          leadingText: '🐉',
          label: 'đặt thẻ này làm mục tiêu?',
          subtitle: 'Thanh chỉ tiêu phía trên sẽ đếm theo thẻ này.',
          onTap: () {
            store.setGoal(note.id);
            _snack(context, 'Đã đặt "${note.displayTitle}" làm thẻ mục tiêu.');
          },
        ),
      SheetItem(
        icon: Icons.bolt,
        iconColor: Colors.amberAccent,
        label: 'đặt thẻ này dẫn đầu nhóm chương',
        onTap: () => store.makeGroupHead(note.id),
      ),
      if (hasHeads)
        SheetItem(
          icon: Icons.low_priority,
          label: 'sử dụng thẻ này làm 1 chương?',
          subtitle: 'Chọn nhóm chương để gắn thẻ vào.',
          onTap: () => _pickHeadAndAssign(context, store, note),
        ),
      SheetItem(
        icon: Icons.delete_outline,
        iconColor: Colors.redAccent,
        label: 'Xóa thẻ (chuyển vào thùng rác)',
        onTap: () => _confirmTrashNote(context, store, note),
      ),
    ],
  );
}

Future<void> _pickHeadAndAssign(
    BuildContext context, NoteStore store, Note note) async {
  final head = await pickNoteDialog(
    context,
    title: 'Chọn nhóm chương',
    items: store.heads,
  );
  if (head == null) return;
  store.assignToGroup(note.id, head.id);
}

Future<void> _confirmTrashNote(
    BuildContext context, NoteStore store, Note note) async {
  final ok = await confirmDialog(
    context,
    title: 'Xóa bài viết?',
    message:
        '"${note.displayTitle}" sẽ được chuyển vào thùng rác và giữ trong $kTrashDays ngày. Bạn có thể khôi phục trong thời gian đó.',
    confirmLabel: 'Xóa',
  );
  if (ok) store.moveToTrash(note.id);
}

/// Menu nhấn giữ thẻ dẫn đầu.
Future<void> showHeadMenu(
  BuildContext context,
  NoteStore store,
  Note head, {
  VoidCallback? onDeleted,
}) {
  return _showSheet(
    context,
    title: head.displayTitle,
    items: [
      SheetItem(
        icon: Icons.edit_outlined,
        label: 'Đổi tên nhóm',
        onTap: () => _renameGroup(context, store, head),
      ),
      SheetItem(
        icon: Icons.delete_outline,
        iconColor: Colors.redAccent,
        label: 'Xóa thẻ dẫn đầu',
        onTap: () async {
          final removed = await deleteGroupHead(context, store, head);
          if (removed && context.mounted) onDeleted?.call();
        },
      ),
    ],
  );
}

Future<void> _renameGroup(
    BuildContext context, NoteStore store, Note head) async {
  final name = await showInputDialog(
    context,
    title: 'Đổi tên nhóm',
    initial: head.title,
    hint: 'Tên nhóm...',
  );
  if (name == null || name.isEmpty) return;
  store.renameGroup(head.id, name);
}

/// Menu nhấn giữ chương.
Future<void> showChapterMenu(
    BuildContext context, NoteStore store, Note chapter) {
  return _showSheet(
    context,
    title: chapter.displayTitle,
    items: [
      SheetItem(
        icon: Icons.link_off,
        label: 'Gỡ khỏi nhóm',
        subtitle: 'Chương trở thành thẻ độc lập.',
        onTap: () => store.removeFromGroup(chapter.id),
      ),
      SheetItem(
        icon: Icons.delete_outline,
        iconColor: Colors.redAccent,
        label: 'Xóa cả chương này, bạn chắc chứ?',
        onTap: () async {
          final ok = await confirmDialog(
            context,
            title: 'Xóa cả chương này, bạn chắc chứ?',
            message:
                '"${chapter.displayTitle}" sẽ vào thùng rác và giữ trong $kTrashDays ngày.',
            confirmLabel: 'Xóa',
          );
          if (ok) store.moveToTrash(chapter.id);
        },
      ),
    ],
  );
}

/// Xóa thẻ dẫn đầu. Trả về true nếu thẻ dẫn đầu đã bị đưa vào thùng rác.
Future<bool> deleteGroupHead(
    BuildContext context, NoteStore store, Note head) async {
  final chapters = store.chaptersOf(head.id);

  if (chapters.isEmpty) {
    final ok = await confirmDialog(
      context,
      title: 'Xóa thẻ dẫn đầu?',
      message:
          '"${head.displayTitle}" sẽ được chuyển vào thùng rác và giữ trong $kTrashDays ngày.',
      confirmLabel: 'Xóa',
    );
    if (!ok) return false;
    store.moveToTrash(head.id);
    return true;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetColor,
      shape: dialogShape(),
      title: const Text('Xóa thẻ dẫn đầu',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: Text(
        'Nhóm này có ${chapters.length} chương. Bạn muốn xóa thế nào?',
        style: const TextStyle(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'only'),
          child: Text('Chỉ xóa thẻ dẫn đầu',
              style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'all'),
          child: const Text('Xóa tất cả nội dung đã ghi',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );

  if (choice == 'only') {
    if (!context.mounted) return false;
    final pick = await pickNoteDialog(
      context,
      title: 'Chọn chương làm dẫn đầu mới',
      items: chapters,
    );
    if (pick == null) return false;
    store.deleteHeadOnly(head.id, newHeadId: pick.id);
    return true;
  }

  if (choice == 'all') {
    if (!context.mounted) return false;
    final ok = await confirmDialog(
      context,
      title: 'Xóa tất cả nội dung?',
      message:
          'Thẻ dẫn đầu và toàn bộ ${chapters.length} chương sẽ vào thùng rác trong $kTrashDays ngày. Hãy suy nghĩ kỹ trước khi xóa.',
      confirmLabel: 'Xóa tất cả',
    );
    if (!ok) return false;
    store.trashGroup(head.id);
    return true;
  }

  return false;
}

// ===== Nội dung gốc: lib/widgets/note_card.dart =====

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.isGrid,
    required this.themeColor,
    required this.isGoal,
    required this.onTap,
    required this.onLongPress,
    required this.onTogglePin,
    this.chapterCount,
    this.groupWords,
  });

  final Note note;
  final bool isGrid;
  final Color themeColor;
  final bool isGoal;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTogglePin;

  /// Chỉ dùng cho thẻ dẫn đầu.
  final int? chapterCount;
  final int? groupWords;

  @override
  Widget build(BuildContext context) {
    final isHead = note.isGroupHead;

    final Color borderColor = isGoal
        ? Colors.amber.fade(0.7)
        : isHead
            ? Colors.amber.fade(0.5)
            : note.isPinned
                ? themeColor.fade(0.5)
                : Colors.white10;

    final contentText = Text(
      note.content.isEmpty
          ? (isHead ? '(Chưa có giới thiệu)' : '(Chưa có nội dung)')
          : previewText(note.content),
      maxLines: isGrid ? 3 : 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white60, fontSize: 13),
    );

    final String bottomLeft;
    if (isHead) {
      bottomLeft = '${chapterCount ?? 0} chương · ${groupWords ?? note.words} từ';
    } else if (isGoal) {
      bottomLeft = '${note.words} / ${note.goalTarget} từ';
    } else {
      bottomLeft = '${note.words} từ';
    }

    final card = Container(
      margin: EdgeInsets.only(bottom: isGrid ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.fade(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: isGrid ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isHead)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.bolt, size: 16, color: Colors.amberAccent),
                ),
              if (isGoal)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text('🐉', style: TextStyle(fontSize: 14)),
                ),
              if (note.showRecycleBadge)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.recycling,
                      size: 15, color: Colors.lightGreenAccent),
                ),
              Expanded(
                child: Text(
                  note.displayTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: note.isPinned ? 'Bỏ ghim' : 'Ghim bài viết',
                icon: Icon(
                  Icons.push_pin,
                  size: 16,
                  color: note.isPinned ? Colors.amber : Colors.white24,
                ),
                onPressed: onTogglePin,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isGrid) Expanded(child: contentText) else contentText,
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(bottomLeft,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Text(formatDate(note.updatedAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: PressScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      ),
    );
  }
}

// ===== Nội dung gốc: lib/screens/loading_screen.dart =====

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, required this.themeColor});

  final Color themeColor;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: Stack(
        children: [
          SoftBackground(themeColor: widget.themeColor),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(_controller.value);
                    return Transform.scale(
                      scale: 0.9 + 0.1 * t,
                      child: Opacity(opacity: 0.6 + 0.4 * t, child: child),
                    );
                  },
                  child: Icon(Icons.bolt, size: 64, color: widget.themeColor),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Novel App',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white10,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(widget.themeColor),
                      minHeight: 3,
                    ),
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

// ===== Nội dung gốc: lib/screens/home_screen.dart =====

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final NoteStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridMode = true;
  String _searchQuery = '';

  NoteStore get _store => widget.store;

  void _openEditor({Note? note}) {
    Navigator.of(context).push(
      fadeSlideRoute<void>(EditorScreen(store: _store, note: note)),
    );
  }

  void _openGroup(Note head) {
    Navigator.of(context).push(
      fadeSlideRoute<void>(GroupScreen(store: _store, headId: head.id)),
    );
  }

  void _openTrash() {
    _store.purgeExpired();
    Navigator.of(context).push(
      fadeSlideRoute<void>(TrashScreen(store: _store)),
    );
  }

  void _openStarMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StarMenuSheet(store: _store, onOpenTrash: _openTrash),
    );
  }

  List<Note> _visibleNotes() {
    final q = _searchQuery.trim().toLowerCase();
    final items = _store.homeNotes;
    if (q.isEmpty) return items;
    return items.where((n) {
      if (_matches(n, q)) return true;
      if (n.isGroupHead) {
        return _store.chaptersOf(n.id).any((c) => _matches(c, q));
      }
      return false;
    }).toList();
  }

  bool _matches(Note n, String q) =>
      n.title.toLowerCase().contains(q) || n.content.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final notes = _visibleNotes();
        return Scaffold(
          body: Stack(
            children: [
              SoftBackground(themeColor: _store.themeColor),
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
                      Expanded(child: _buildNotesView(notes)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _store.themeColor,
            tooltip: 'Viết bài mới',
            onPressed: () => _openEditor(),
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
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
                icon: Icon(Icons.bolt, color: _store.themeColor, size: 20),
                onPressed: () => showAppInfoDialog(context),
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
        Expanded(child: _buildGoalBox()),
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
            onPressed: () => setState(() => _isGridMode = !_isGridMode),
          ),
        ),
      ],
    );
  }

  Widget _buildGoalBox() {
    final goal = _store.goalNote;
    final target = _store.goalTarget;
    final words = goal?.words ?? 0;
    final ratio = target > 0 ? words / target : 0.0;
    final progress = ratio > 1.0 ? 1.0 : ratio;
    final line1 =
        goal == null ? 'chào mừng đã đến với app' : '🐉 ${goal.displayTitle}';
    final line2 = goal == null
        ? 'Nhấn giữ một thẻ để đặt làm mục tiêu'
        : '$words / $target từ';

    return GestureDetector(
      onTap: () => showGoalDialog(context, _store),
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
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white10,
                valueColor:
                    AlwaysStoppedAnimation<Color>(_store.themeColor),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
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
      final message = _store.homeNotes.isEmpty
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

    const padding = EdgeInsets.only(bottom: 88);

    if (_isGridMode) {
      return GridView.builder(
        padding: padding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 168,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: notes.length,
        itemBuilder: (context, index) =>
            _buildCard(notes[index], isGrid: true),
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: notes.length,
      itemBuilder: (context, index) =>
          _buildCard(notes[index], isGrid: false),
    );
  }

  Widget _buildCard(Note note, {required bool isGrid}) {
    final isHead = note.isGroupHead;
    return NoteCard(
      key: ValueKey(note.id),
      note: note,
      isGrid: isGrid,
      themeColor: _store.themeColor,
      isGoal: _store.goalNoteId == note.id,
      chapterCount: isHead ? _store.chaptersOf(note.id).length : null,
      groupWords: isHead ? _store.groupWordCount(note.id) : null,
      onTap: () => isHead ? _openGroup(note) : _openEditor(note: note),
      onLongPress: () => isHead
          ? showHeadMenu(context, _store, note)
          : showNoteMenu(context, _store, note),
      onTogglePin: () => _store.togglePin(note.id),
    );
  }
}

// ===== Nội dung gốc: lib/screens/group_screen.dart =====

/// Màn mục lục của một nhóm chương.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.store, required this.headId});

  final NoteStore store;
  final String headId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late final TextEditingController _introCtrl = TextEditingController(
    text: widget.store.findNote(widget.headId)?.content ?? '',
  );

  @override
  void dispose() {
    _introCtrl.dispose();
    super.dispose();
  }

  void _openChapter(Note chapter) {
    Navigator.of(context).push(
      fadeSlideRoute<void>(EditorScreen(store: widget.store, note: chapter)),
    );
  }

  void _addChapter() {
    Navigator.of(context).push(
      fadeSlideRoute<void>(
        EditorScreen(store: widget.store, groupId: widget.headId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final head = store.findNote(widget.headId);

        if (head == null || !head.isGroupHead) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold(backgroundColor: kBgColor);
        }

        final chapters = store.chaptersOf(head.id);
        final total = store.groupWordCount(head.id);
        void closeIfDeleted() {
          if (mounted) Navigator.of(context).pop();
        }

        return Scaffold(
          backgroundColor: kBgColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Tùy chọn nhóm',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => showHeadMenu(
                  context,
                  store,
                  head,
                  onDeleted: closeIfDeleted,
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: store.themeColor,
            tooltip: 'Thêm chương',
            onPressed: _addChapter,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
          body: SafeArea(
            child: Column(
              children: [
                GestureDetector(
                  onLongPress: () => showHeadMenu(
                    context,
                    store,
                    head,
                    onDeleted: closeIfDeleted,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      head.displayTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${chapters.length} chương · $total từ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    controller: _introCtrl,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 14, color: kWhite90),
                    onChanged: (text) =>
                        store.updateNote(head.id, title: head.title, content: text),
                    decoration: InputDecoration(
                      hintText: 'Giới thiệu nhóm (tùy chọn)...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.fade(0.04),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 12),
                Expanded(
                  child: chapters.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có chương nào.\nNhấn nút + để thêm chương.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, height: 1.5),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          buildDefaultDragHandles: false,
                          itemCount: chapters.length,
                          onReorder: (oldIndex, newIndex) {
                            var target = newIndex;
                            if (target > oldIndex) target -= 1;
                            final ids = chapters.map((c) => c.id).toList();
                            final moved = ids.removeAt(oldIndex);
                            ids.insert(target, moved);
                            store.reorderChapters(head.id, ids);
                          },
                          itemBuilder: (context, index) {
                            final chapter = chapters[index];
                            return _ChapterTile(
                              key: ValueKey(chapter.id),
                              index: index,
                              chapter: chapter,
                              themeColor: store.themeColor,
                              onTap: () => _openChapter(chapter),
                              onLongPress: () =>
                                  showChapterMenu(context, store, chapter),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    super.key,
    required this.index,
    required this.chapter,
    required this.themeColor,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final Note chapter;
  final Color themeColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            color: Colors.white.fade(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: themeColor, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text('${chapter.words} từ',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.drag_handle, color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Nội dung gốc: lib/screens/editor_screen.dart =====

class _Snap {
  const _Snap(this.title, this.content, this.cursor);

  final String title;
  final String content;
  final int cursor;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.store,
    this.note,
    this.groupId,
  });

  final NoteStore store;

  /// Bài đang sửa (null = bài mới).
  final Note? note;

  /// Nhóm đích khi tạo chương mới.
  final String? groupId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _contentCtrl =
      TextEditingController(text: widget.note?.content ?? '');

  String? _noteId;
  String _savedTitle = '';
  String _savedContent = '';

  // Hoàn tác: gộp ký tự gõ liên tiếp khi dừng 1 giây.
  final List<_Snap> _history = [];
  late _Snap _lastSnap;
  bool _bursting = false;
  bool _applyingHistory = false;
  Timer? _burstTimer;
  Timer? _saveTimer;

  // Chỉ tiêu và nhắc nghỉ.
  late final bool _isGoal;
  late final int _goalTarget;
  late bool _reminded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noteId = widget.note?.id;
    _savedTitle = widget.note?.title ?? '';
    _savedContent = widget.note?.content ?? '';
    _lastSnap = _currentSnap();
    _isGoal = widget.note != null &&
        widget.store.goalNoteId == widget.note!.id;
    _goalTarget = widget.store.goalTarget;
    _reminded = _isGoal && countWords(_contentCtrl.text) >= _goalTarget;
    _titleCtrl.addListener(_onTextChanged);
    _contentCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _burstTimer?.cancel();
    _saveTimer?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flush();
  }

  _Snap _currentSnap() {
    final sel = _contentCtrl.selection;
    final cursor = sel.isValid ? sel.baseOffset : _contentCtrl.text.length;
    return _Snap(_titleCtrl.text, _contentCtrl.text, cursor < 0 ? 0 : cursor);
  }

  void _onTextChanged() {
    if (_applyingHistory) return;
    final snap = _currentSnap();
    if (snap.title == _lastSnap.title && snap.content == _lastSnap.content) {
      return;
    }

    final bulk =
        (snap.content.length - _lastSnap.content.length).abs() > 1 ||
            (snap.title.length - _lastSnap.title.length).abs() > 1;

    if (bulk) {
      // Xóa, dán, cắt nhiều chữ: là một bước riêng.
      _pushHistory(_lastSnap);
      _bursting = false;
    } else if (!_bursting) {
      _pushHistory(_lastSnap);
      _bursting = true;
    }

    _lastSnap = snap;
    _burstTimer?.cancel();
    _burstTimer = Timer(const Duration(seconds: 1), () {
      _bursting = false;
    });

    _scheduleSave();
    _checkGoalReminder();
  }

  void _pushHistory(_Snap snap) {
    _history.add(snap);
    if (_history.length > 200) _history.removeAt(0);
    setState(() {});
  }

  void _undo() {
    if (_history.isEmpty) return;
    final snap = _history.removeLast();
    _applyingHistory = true;
    _titleCtrl.value = TextEditingValue(
      text: snap.title,
      selection: TextSelection.collapsed(offset: snap.title.length),
    );
    final len = snap.content.length;
    _contentCtrl.value = TextEditingValue(
      text: snap.content,
      selection: TextSelection.collapsed(
        offset: snap.cursor > len ? len : snap.cursor,
      ),
    );
    _applyingHistory = false;
    _lastSnap = snap;
    _bursting = false;
    _burstTimer?.cancel();
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _flush);
  }

  /// Đẩy nội dung vào store. Bài mới trống thì không lưu.
  void _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text;
    if (title == _savedTitle && content == _savedContent) return;

    final id = _noteId;
    if (id == null) {
      if (title.isEmpty && content.trim().isEmpty) return;
      final created = widget.store.createNote(
        title: title,
        content: content,
        groupId: widget.groupId,
      );
      _noteId = created.id;
    } else {
      widget.store.updateNote(id, title: title, content: content);
    }
    _savedTitle = title;
    _savedContent = content;
  }

  void _checkGoalReminder() {
    if (!_isGoal) return;
    final words = countWords(_contentCtrl.text);
    if (words < _goalTarget) {
      _reminded = false;
      return;
    }
    if (_reminded) return;
    _reminded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showRestReminder(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (_) => _flush(),
      child: Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _contentCtrl,
            builder: (context, value, _) {
              final words = countWords(value.text);
              return Text(
                _isGoal ? '🐉 $words / $_goalTarget từ' : '$words từ',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              );
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Hoàn tác',
              icon: const Icon(Icons.undo),
              onPressed: _history.isEmpty ? null : _undo,
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
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
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
                    controller: _contentCtrl,
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
      ),
    );
  }
}

// ===== Nội dung gốc: lib/screens/trash_screen.dart =====

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.store});

  final NoteStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final entries = store.trashEntries;
        return Scaffold(
          backgroundColor: kBgColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Thùng rác', style: TextStyle(fontSize: 16)),
            actions: [
              if (entries.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmEmpty(context),
                  child: const Text('Dọn sạch',
                      style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(
                  child: Text(
                    'Thùng rác trống.\nBài bị xóa được giữ 30 ngày.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, height: 1.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, entries[index]),
                ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, List<Note> entry) {
    final primary = store.primaryOf(entry);
    final isGroup = primary.trashGroupId != null && primary.isGroupHead;
    final chapters = entry.where((n) => !n.isGroupHead).length;
    final words = entry.fold<int>(0, (sum, n) => sum + n.words);
    final left = trashDaysLeft(primary);
    final title = isGroup
        ? '${primary.displayTitle} ($chapters chương)'
        : primary.displayTitle;

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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '$words từ · còn $left ngày',
                  style: TextStyle(
                    fontSize: 12,
                    color: left <= 3 ? Colors.redAccent : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Khôi phục',
            icon: const Icon(Icons.recycling, color: Colors.lightGreenAccent),
            onPressed: () {
              store.restoreEntry(primary);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã khôi phục bài viết.')),
              );
            },
          ),
          IconButton(
            tooltip: 'Xóa vĩnh viễn',
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            onPressed: () => _confirmDeleteForever(context, primary),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteForever(BuildContext context, Note primary) async {
    final ok = await confirmDialog(
      context,
      title: 'Xóa vĩnh viễn?',
      message: 'Bài viết này sẽ mất và không thể khôi phục.',
      confirmLabel: 'Xóa',
    );
    if (ok) store.deleteForeverEntry(primary);
  }

  Future<void> _confirmEmpty(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Dọn sạch thùng rác?',
      message: 'Tất cả bài trong thùng rác sẽ mất vĩnh viễn.',
      confirmLabel: 'Dọn sạch',
    );
    if (ok) store.emptyTrash();
  }
}

// ===== Nội dung gốc: lib/screens/star_menu_sheet.dart =====

enum _ExportFormat { txt, markdown }

/// Bảng ngôi sao: chuỗi ngày, thùng rác, màu chủ đề, xuất file.
class StarMenuSheet extends StatefulWidget {
  const StarMenuSheet({
    super.key,
    required this.store,
    required this.onOpenTrash,
  });

  final NoteStore store;
  final VoidCallback onOpenTrash;

  @override
  State<StarMenuSheet> createState() => _StarMenuSheetState();
}

class _StarMenuSheetState extends State<StarMenuSheet> {
  String? _exportId;
  _ExportFormat _format = _ExportFormat.txt;

  NoteStore get _store => widget.store;
  bool get _isMd => _format == _ExportFormat.markdown;
  String get _extension => _isMd ? 'md' : 'txt';

  Note? _selected() {
    final id = _exportId;
    if (id == null) return null;
    for (final n in _store.homeNotes) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: kSheetColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: _children(context),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _children(BuildContext context) {
    final theme = _store.themeColor;
    final streak = _store.streakDays;
    final streakText = streak <= 0
        ? 'Hãy viết hôm nay để bắt đầu chuỗi!'
        : '🔥 $streak ngày viết liên tiếp';
    final selected = _selected();
    final homeItems = _store.homeNotes;

    return [
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

      // Chuỗi ngày
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.fade(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.fade(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department,
                color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(streakText,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // Thùng rác
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
              const Icon(Icons.delete_outline, color: Colors.lightGreenAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Thùng rác (${_store.trashCount})',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),

      // Màu chủ đề
      const Text('Màu chủ đề',
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: kThemeColors.map((color) {
          final isSelected = color.value == theme.value;
          return GestureDetector(
            onTap: () => _store.setTheme(color),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 28),

      // Xuất file
      const Text('Xuất file',
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String?>(
        value: selected?.id,
        isExpanded: true,
        dropdownColor: const Color(0xFF1F1F27),
        decoration: const InputDecoration(
          labelText: 'Chọn bài viết',
          labelStyle: TextStyle(color: Colors.white54),
        ),
        style: const TextStyle(color: Colors.white),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Tất cả bài viết'),
          ),
          ...homeItems.map(
            (n) => DropdownMenuItem<String?>(
              value: n.id,
              child: Text(n.displayTitle, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _exportId = value),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _formatChip('TXT (văn bản)', _ExportFormat.txt)),
          const SizedBox(width: 10),
          Expanded(
              child: _formatChip('Markdown (.md)', _ExportFormat.markdown)),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: homeItems.isEmpty ? null : _exportFile,
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
          onPressed: homeItems.isEmpty ? null : _copyToClipboard,
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Chỉ sao chép nội dung'),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Bấm "Xuất file" để lưu file vào thư mục Download. Nếu máy không cho '
        'phép, nội dung sẽ được sao chép vào bộ nhớ tạm. Xuất một nhóm sẽ kèm '
        'toàn bộ chương của nhóm.',
        style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
      ),
    ];
  }

  Widget _formatChip(String label, _ExportFormat value) {
    final selected = _format == value;
    final theme = _store.themeColor;
    return GestureDetector(
      onTap: () => setState(() => _format = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.fade(0.25) : Colors.white.fade(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? theme : Colors.white12),
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

  String _buildFileName() {
    final selected = _selected();
    var base =
        selected == null ? 'novel_app_tat_ca_bai_viet' : selected.displayTitle;
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();
    if (base.isEmpty) base = 'bai_viet';
    if (base.length > 60) base = base.substring(0, 60);
    return '$base.$_extension';
  }

  String _buildText() => buildExportText(_store, _selected()?.id, _isMd);

  Future<void> _exportFile() async {
    final text = _buildText();
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
    } catch (_) {
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
    await Clipboard.setData(ClipboardData(text: _buildText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép nội dung vào bộ nhớ tạm.')),
    );
  }
}

/// Gom nội dung xuất. Một nhóm sẽ kèm toàn bộ chương bên trong.
String buildExportText(NoteStore store, String? singleId, bool markdown) {
  List<Note> roots;
  if (singleId == null) {
    roots = store.homeNotes;
  } else {
    final note = store.findNote(singleId);
    roots = note == null ? <Note>[] : [note];
  }

  final buffer = StringBuffer();
  for (final note in roots) {
    _writeNote(buffer, note, markdown, heading: 1);
    if (note.isGroupHead) {
      for (final chapter in store.chaptersOf(note.id)) {
        _writeNote(buffer, chapter, markdown, heading: 2);
      }
    }
  }
  return buffer.toString().trim();
}

void _writeNote(StringBuffer buffer, Note note, bool markdown,
    {required int heading}) {
  final title = note.displayTitle;
  if (markdown) {
    buffer.writeln('${'#' * heading} $title');
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
