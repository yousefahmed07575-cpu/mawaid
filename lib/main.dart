import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ═══════════════════════════════════════════════════════
//                    نقطة البداية
// ═══════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Africa/Cairo'));

  await StorageService.init();
  await NotificationService.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MawaidApp());
}

class MawaidApp extends StatelessWidget {
  const MawaidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'مواعيد',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('ar', 'EG'),
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//                    الألوان
// ═══════════════════════════════════════════════════════

class AppColors {
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color accent = Color(0xFF00BCD4);
  static const Color background = Color(0xFFF5F7FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1E1E1E);
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color pomodoroWork = Color(0xFFE53935);
  static const Color pomodoroBreak = Color(0xFF43A047);
}

// ═══════════════════════════════════════════════════════
//                    الثيم
// ═══════════════════════════════════════════════════════

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.cardDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cardDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('darkMode') ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _isDarkMode);
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════
//                    الموديلات
// ═══════════════════════════════════════════════════════

enum RepeatType { once, daily, specificDays }

class Appointment {
  String id;
  String title;
  int hour;
  int minute;
  String audioPath;
  RepeatType repeatType;
  List<int> selectedDays;
  bool isActive;
  DateTime createdAt;

  Appointment({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.audioPath = '',
    this.repeatType = RepeatType.once,
    this.selectedDays = const [],
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get time12String {
    final period = hour >= 12 ? 'م' : 'ص';
    final h12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$h12:$m $period';
  }

  String get repeatDescription {
    switch (repeatType) {
      case RepeatType.once:
        return 'مرة واحدة';
      case RepeatType.daily:
        return 'كل يوم';
      case RepeatType.specificDays:
        if (selectedDays.isEmpty) return 'أيام محددة';
        final names = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];
        return selectedDays.map((d) => names[d]).join('، ');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'hour': hour,
        'minute': minute,
        'audioPath': audioPath,
        'repeatType': repeatType.index,
        'selectedDays': selectedDays,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String,
        title: json['title'] as String,
        hour: json['hour'] as int,
        minute: json['minute'] as int,
        audioPath: json['audioPath'] as String? ?? '',
        repeatType: RepeatType.values[json['repeatType'] as int],
        selectedDays: List<int>.from(json['selectedDays'] as List),
        isActive: json['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class PomodoroSettings {
  int workMinutes;
  int breakMinutes;
  String startAudioPath;
  String breakAudioPath;

  PomodoroSettings({
    this.workMinutes = 20,
    this.breakMinutes = 5,
    this.startAudioPath = '',
    this.breakAudioPath = '',
  });

  Map<String, dynamic> toJson() => {
        'workMinutes': workMinutes,
        'breakMinutes': breakMinutes,
        'startAudioPath': startAudioPath,
        'breakAudioPath': breakAudioPath,
      };

  factory PomodoroSettings.fromJson(Map<String, dynamic> json) =>
      PomodoroSettings(
        workMinutes: json['workMinutes'] as int? ?? 20,
        breakMinutes: json['breakMinutes'] as int? ?? 5,
        startAudioPath: json['startAudioPath'] as String? ?? '',
        breakAudioPath: json['breakAudioPath'] as String? ?? '',
      );
}

class StudySession {
  String id;
  DateTime startTime;
  DateTime endTime;
  int durationMinutes;

  StudySession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationMinutes': durationMinutes,
      };

  factory StudySession.fromJson(Map<String, dynamic> json) => StudySession(
        id: json['id'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        durationMinutes: json['durationMinutes'] as int,
      );
}

class StudyStatistics {
  final int todayMinutes;
  final int weekMinutes;
  final int monthMinutes;
  final int totalMinutes;
  final int totalSessions;

  StudyStatistics({
    this.todayMinutes = 0,
    this.weekMinutes = 0,
    this.monthMinutes = 0,
    this.totalMinutes = 0,
    this.totalSessions = 0,
  });

  static String formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes دقيقة';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h ساعة';
    return '$h ساعة و $m دقيقة';
  }

  String get todayFormatted => formatMinutes(todayMinutes);
  String get weekFormatted => formatMinutes(weekMinutes);
  String get monthFormatted => formatMinutes(monthMinutes);
  String get totalFormatted => formatMinutes(totalMinutes);
}
// ═══════════════════════════════════════════════════════
//                    الخدمات
// ═══════════════════════════════════════════════════════

class StorageService {
  static late SharedPreferences _prefs;
  static const String _appointmentsKey = 'appointments';
  static const String _pomodoroKey = 'pomodoro';
  static const String _sessionsKey = 'sessions';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── المواعيد ───
  static List<Appointment> getAppointments() {
    final data = _prefs.getString(_appointmentsKey);
    if (data == null || data.isEmpty) return [];
    final list = jsonDecode(data) as List;
    return list
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAppointments(List<Appointment> list) async {
    final data = jsonEncode(list.map((e) => e.toJson()).toList());
    await _prefs.setString(_appointmentsKey, data);
  }

  // ─── البومودورو ───
  static PomodoroSettings getPomodoroSettings() {
    final data = _prefs.getString(_pomodoroKey);
    if (data == null || data.isEmpty) return PomodoroSettings();
    return PomodoroSettings.fromJson(
        jsonDecode(data) as Map<String, dynamic>);
  }

  static Future<void> savePomodoroSettings(PomodoroSettings s) async {
    await _prefs.setString(_pomodoroKey, jsonEncode(s.toJson()));
  }

  // ─── الجلسات ───
  static List<StudySession> getSessions() {
    final data = _prefs.getString(_sessionsKey);
    if (data == null || data.isEmpty) return [];
    final list = jsonDecode(data) as List;
    return list
        .map((e) => StudySession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSessions(List<StudySession> list) async {
    final data = jsonEncode(list.map((e) => e.toJson()).toList());
    await _prefs.setString(_sessionsKey, data);
  }

  static Future<void> addSession(StudySession s) async {
    final list = getSessions();
    list.add(s);
    await saveSessions(list);
  }

  // ─── الإحصائيات ───
  static StudyStatistics getStatistics() {
    final sessions = getSessions();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    int today = 0, week = 0, month = 0, total = 0;
    for (final s in sessions) {
      total += s.durationMinutes;
      if (s.startTime.isAfter(todayStart)) today += s.durationMinutes;
      if (s.startTime.isAfter(weekStart)) week += s.durationMinutes;
      if (s.startTime.isAfter(monthStart)) month += s.durationMinutes;
    }

    return StudyStatistics(
      todayMinutes: today,
      weekMinutes: week,
      monthMinutes: month,
      totalMinutes: total,
      totalSessions: sessions.length,
    );
  }

  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {},
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleAppointment(Appointment a) async {
    await cancelAppointment(a.id);

    if (!a.isActive) return;

    final androidDetails = AndroidNotificationDetails(
      'appointments_channel',
      'المواعيد',
      channelDescription: 'تذكيرات المواعيد',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: a.audioPath.isNotEmpty ? RawResourceAndroidNotificationSound(a.audioPath) : null,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    final details = NotificationDetails(android: androidDetails);

    if (a.repeatType == RepeatType.daily) {
      await _plugin.periodicallyShow(
        a.id.hashCode,
        'موعد: ${a.title}',
        'الوقت الآن ${a.time12String}',
        RepeatInterval.daily,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } else {
      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, a.hour, a.minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        a.id.hashCode,
        'موعد: ${a.title}',
        'الوقت الآن ${a.time12String}',
        tz.TZDateTime.from(scheduled, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  static Future<void> cancelAppointment(String id) async {
    await _plugin.cancel(id.hashCode);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

class AudioService {
  static final AudioRecorder _recorder = AudioRecorder();
  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;

  static bool get isPlaying => _isPlaying;

  static Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  static Future<String?> startRecording() async {
    if (!await requestMicPermission()) return null;

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    return path;
  }

  static Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  static Future<void> play(String path, {bool loop = false}) async {
    if (path.isEmpty) return;
    _isPlaying = true;
    await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    await _player.play(DeviceFileSource(path));
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
    });
  }

  static Future<void> stop() async {
    _isPlaying = false;
    await _player.stop();
  }
}

// ═══════════════════════════════════════════════════════
//                    الشاشات
// ═══════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.notifications_active,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'مواعيد',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'منبه المذاكرة',
              style: TextStyle(fontSize: 18, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── الشاشة الرئيسية ───
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [
    AppointmentsScreen(),
    PomodoroScreen(),
    StatisticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.list), label: 'المواعيد'),
          NavigationDestination(
              icon: Icon(Icons.timer), label: 'مذاكرة'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'إحصائيات'),
          NavigationDestination(
              icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ─── شاشة المواعيد ───
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Appointment> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _appointments = StorageService.getAppointments();
    });
  }

  Future<void> _delete(String id) async {
    final list = StorageService.getAppointments();
    list.removeWhere((a) => a.id == id);
    await StorageService.saveAppointments(list);
    await NotificationService.cancelAppointment(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📅 المواعيد')),
      body: _appointments.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('مفيش مواعيد لسه', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('اضغط + لإضافة موعد',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _appointments.length,
              itemBuilder: (_, i) {
                final a = _appointments[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications,
                          color: AppColors.primary),
                    ),
                    title: Text(a.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('🕐 ${a.time12String}'),
                        Text('🔁 ${a.repeatDescription}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (a.audioPath.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.play_arrow,
                                color: AppColors.success),
                            onPressed: () => AudioService.play(a.audioPath),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.error),
                          onPressed: () => _delete(a.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddAppointmentScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة موعد'),
      ),
    );
  }
}

// ─── شاشة إضافة موعد ───
class AddAppointmentScreen extends StatefulWidget {
  const AddAppointmentScreen({super.key});
  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  final _titleCtrl = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  RepeatType _repeat = RepeatType.once;
  List<int> _days = [];
  String _audioPath = '';
  bool _isRecording = false;
  String? _playingId;

  final _dayNames = [
    'السبت', 'الأحد', 'الاثنين', 'الثلاثاء',
    'الأربعاء', 'الخميس', 'الجمعة'
  ];

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await AudioService.stopRecording();
      setState(() {
        _isRecording = false;
        if (path != null) _audioPath = path;
      });
    } else {
      final path = await AudioService.startRecording();
      if (path != null) {
        setState(() {
          _isRecording = true;
          _audioPath = path;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم الموعد')),
      );
      return;
    }

    final a = Appointment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleCtrl.text.trim(),
      hour: _time.hour,
      minute: _time.minute,
      audioPath: _audioPath,
      repeatType: _repeat,
      selectedDays: _days,
    );

    final list = StorageService.getAppointments();
    list.add(a);
    await StorageService.saveAppointments(list);
    await NotificationService.scheduleAppointment(a);

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('➕ إضافة موعد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('اسم الموعد', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(hintText: 'مثال: يوسف - رياضة'),
          ),
          const SizedBox(height: 20),

          const Text('الوقت', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.access_time, color: AppColors.primary),
              title: Text(_time.format(context)),
              trailing: const Icon(Icons.edit),
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 20),

          const Text('التكرار', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          RadioListTile<RepeatType>(
            value: RepeatType.once,
            groupValue: _repeat,
            title: const Text('مرة واحدة'),
            onChanged: (v) => setState(() => _repeat = v!),
          ),
          RadioListTile<RepeatType>(
            value: RepeatType.daily,
            groupValue: _repeat,
            title: const Text('كل يوم'),
            onChanged: (v) => setState(() => _repeat = v!),
          ),
          RadioListTile<RepeatType>(
            value: RepeatType.specificDays,
            groupValue: _repeat,
            title: const Text('أيام محددة'),
            onChanged: (v) => setState(() => _repeat = v!),
          ),

          if (_repeat == RepeatType.specificDays) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final selected = _days.contains(i);
                return FilterChip(
                  label: Text(_dayNames[i]),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _days.add(i);
                      } else {
                        _days.remove(i);
                      }
                    });
                  },
                );
              }),
            ),
          ],

          const SizedBox(height: 20),
          const Text('الصوت', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'إيقاف التسجيل' : 'تسجيل صوت'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isRecording ? AppColors.error : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_audioPath.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow,
                      color: AppColors.success, size: 32),
                  onPressed: () {
                    AudioService.play(_audioPath);
                  },
                ),
            ],
          ),

          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الموعد'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
// ─── شاشة البومودورو ───
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});
  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  PomodoroSettings _settings = PomodoroSettings();
  Timer? _timer;
  int _secondsLeft = 0;
  int _workMinutes = 20;
  int _breakMinutes = 5;
  bool _isWorking = false;
  bool _isRunning = false;
  bool _isBreak = false;
  int _sessionCount = 0;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final s = StorageService.getPomodoroSettings();
    setState(() {
      _settings = s;
      _workMinutes = s.workMinutes;
      _breakMinutes = s.breakMinutes;
      _secondsLeft = _workMinutes * 60;
    });
  }

  void _startWork() {
    setState(() {
      _isWorking = true;
      _isRunning = true;
      _isBreak = false;
      _secondsLeft = _workMinutes * 60;
      _sessionStart = DateTime.now();
    });
    if (_settings.startAudioPath.isNotEmpty) {
      AudioService.play(_settings.startAudioPath, loop: true);
    }
    _startTimer();
  }

  void _startBreak() {
    setState(() {
      _isBreak = true;
      _isRunning = true;
      _secondsLeft = _breakMinutes * 60;
    });
    if (_settings.breakAudioPath.isNotEmpty) {
      AudioService.play(_settings.breakAudioPath, loop: true);
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        _onTimerEnd();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _onTimerEnd() async {
    await AudioService.stop();

    if (!_isBreak && _sessionStart != null) {
      final now = DateTime.now();
      final dur = now.difference(_sessionStart!).inMinutes;
      if (dur > 0) {
        await StorageService.addSession(StudySession(
          id: now.millisecondsSinceEpoch.toString(),
          startTime: _sessionStart!,
          endTime: now,
          durationMinutes: dur,
        ));
      }
      _sessionCount++;
    }

    if (_isBreak) {
      _startWork();
    } else {
      _startBreak();
    }
  }

  void _pause() {
    _timer?.cancel();
    AudioService.stop();
    setState(() => _isRunning = false);
  }

  void _resume() {
    setState(() => _isRunning = true);
    _startTimer();
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await AudioService.stop();
    setState(() {
      _isWorking = false;
      _isRunning = false;
      _isBreak = false;
      _secondsLeft = _workMinutes * 60;
    });
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    AudioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⏱️ المذاكرة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PomodoroSettingsScreen(settings: _settings)),
              );
              _loadSettings();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // معلومات الجلسة
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoColumn('الجلسات', '$_sessionCount'),
                    _infoColumn('مذاكرة', '$_workMinutes د'),
                    _infoColumn('راحة', '$_breakMinutes د'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // الدائرة
            Expanded(
              child: Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBreak
                        ? AppColors.pomodoroBreak.withOpacity(0.1)
                        : AppColors.pomodoroWork.withOpacity(0.1),
                    border: Border.all(
                      color: _isBreak
                          ? AppColors.pomodoroBreak
                          : AppColors.pomodoroWork,
                      width: 6,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isBreak ? Icons.coffee : Icons.menu_book,
                        size: 50,
                        color: _isBreak
                            ? AppColors.pomodoroBreak
                            : AppColors.pomodoroWork,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isBreak ? 'راحة' : 'مذاكرة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _isBreak
                              ? AppColors.pomodoroBreak
                              : AppColors.pomodoroWork,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatTime(_secondsLeft),
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // الأزرار
            if (!_isWorking)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startWork,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ابدأ المذاكرة'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: AppColors.pomodoroWork,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isRunning ? _pause : _resume,
                      icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                      label: Text(_isRunning ? 'إيقاف مؤقت' : 'استكمال'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('إنهاء'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}

// ─── إعدادات البومودورو ───
class PomodoroSettingsScreen extends StatefulWidget {
  final PomodoroSettings settings;
  const PomodoroSettingsScreen({super.key, required this.settings});

  @override
  State<PomodoroSettingsScreen> createState() => _PomodoroSettingsScreenState();
}

class _PomodoroSettingsScreenState extends State<PomodoroSettingsScreen> {
  late int _work;
  late int _break;
  late String _startAudio;
  late String _breakAudio;
  bool _recording = false;
  String _recordingTarget = '';

  @override
  void initState() {
    super.initState();
    _work = widget.settings.workMinutes;
    _break = widget.settings.breakMinutes;
    _startAudio = widget.settings.startAudioPath;
    _breakAudio = widget.settings.breakAudioPath;
  }

  Future<void> _toggleRecord(String target) async {
    if (_recording && _recordingTarget == target) {
      final path = await AudioService.stopRecording();
      setState(() {
        _recording = false;
        if (path != null) {
          if (target == 'start') _startAudio = path;
          if (target == 'break') _breakAudio = path;
        }
      });
    } else {
      if (_recording) {
        await AudioService.stopRecording();
      }
      final path = await AudioService.startRecording();
      if (path != null) {
        setState(() {
          _recording = true;
          _recordingTarget = target;
        });
      }
    }
  }

  Future<void> _save() async {
    final s = PomodoroSettings(
      workMinutes: _work,
      breakMinutes: _break,
      startAudioPath: _startAudio,
      breakAudioPath: _breakAudio,
    );
    await StorageService.savePomodoroSettings(s);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المذاكرة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('وقت المذاكرة (بالدقايق)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: _work.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$_work دقيقة',
            onChanged: (v) => setState(() => _work = v.round()),
          ),
          Center(
              child: Text('$_work دقيقة',
                  style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 20),

          const Text('وقت الراحة (بالدقايق)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: _break.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '$_break دقيقة',
            onChanged: (v) => setState(() => _break = v.round()),
          ),
          Center(
              child: Text('$_break دقيقة',
                  style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 30),

          _audioTile('🔊 صوت "قوم ذاكر"', _startAudio, 'start'),
          const SizedBox(height: 12),
          _audioTile('🔊 صوت "راحة"', _breakAudio, 'break'),

          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audioTile(String label, String path, String target) {
    final isRec = _recording && _recordingTarget == target;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleRecord(target),
                    icon: Icon(isRec ? Icons.stop : Icons.mic),
                    label: Text(isRec ? 'إيقاف' : 'تسجيل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isRec ? AppColors.error : AppColors.primary,
                    ),
                  ),
                ),
                if (path.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.play_arrow,
                        color: AppColors.success, size: 32),
                    onPressed: () => AudioService.play(path),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── شاشة الإحصائيات ───
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late StudyStatistics _stats;

  @override
  void initState() {
    super.initState();
    _stats = StorageService.getStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📊 الإحصائيات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statCard('📅 النهارده', _stats.todayFormatted, AppColors.primary),
          const SizedBox(height: 12),
          _statCard('📆 الأسبوع', _stats.weekFormatted, AppColors.success),
          const SizedBox(height: 12),
          _statCard('🗓️ الشهر', _stats.monthFormatted, AppColors.pomodoroWork),
          const SizedBox(height: 12),
          _statCard('📚 الإجمالي', _stats.totalFormatted, AppColors.accent),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('⏱️ عدد الجلسات',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_stats.totalSessions}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('📈 متوسط الجلسة',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        _stats.totalSessions == 0
                            ? '0 دقيقة'
                            : StudyStatistics.formatMinutes(
                                _stats.totalMinutes ~/ _stats.totalSessions),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.bar_chart, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── شاشة الإعدادات ───
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ الإعدادات')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('الوضع الليلي'),
            value: themeProvider.isDarkMode,
            onChanged: (_) => themeProvider.toggleTheme(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.error),
            title: const Text('مسح كل البيانات',
                style: TextStyle(color: AppColors.error)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('تحذير'),
                  content: const Text(
                      'هيتم مسح كل المواعيد والجلسات. متأكد؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('مسح',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await StorageService.clearAll();
                await NotificationService.cancelAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم مسح كل البيانات')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── شاشة عن التطبيق ───
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ℹ️ عن التطبيق')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  size: 70,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'مواعيد',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('الإصدار 1.0.0',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              const Divider(),
              const SizedBox(height: 20),
              const Text('إعداد', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              const Text(
                'المهندس يوسف أحمد مصطفى',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              const Text('© 2026 - جميع الحقوق محفوظة',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}