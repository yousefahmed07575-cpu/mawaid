// ═══════════════════════════════════════════════════════════════
//  mawaid - تطبيق مواعيد ومنبه المذاكرة
//  المهندس يوسف أحمد مصطفى
//  نسخة آمنة 100% + استرجاع البيانات القديمة
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  ثوابت عامة
// ═══════════════════════════════════════════════════════════════
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

const String kSystemAlarmSound = 'content://settings/system/alarm_alert';
const String kSystemNotifySound =
    'content://settings/system/notification_sound';

// ═══════════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════════
int generateAlarmId(String id) {
  int hash = 0;
  for (int i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.codeUnitAt(i)) & 0x7fffffff;
  }
  return hash;
}

String weekdayNameAr(int w) {
  const names = {
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };
  return names[w] ?? '';
}

const List<int> weekDaysOrder = [6, 7, 1, 2, 3, 4, 5];

// ═══════════════════════════════════════════════════════════════
//  Recurrence Type
// ═══════════════════════════════════════════════════════════════
enum RecurrenceType { once, daily, weekly }

// ═══════════════════════════════════════════════════════════════
//  Main
// ═══════════════════════════════════════════════════════════════
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Alarm.init();
  } catch (e) {
    debugPrint('🔴 Alarm.init error: $e');
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const MawaidApp(),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
//  Models
// ═══════════════════════════════════════════════════════════════
class Appointment {
  final String id;
  String title;
  String note;
  DateTime dateTime;
  String? soundPath;
  RecurrenceType recurrence;
  List<int> weekdays;

  Appointment({
    required this.id,
    required this.title,
    required this.note,
    required this.dateTime,
    this.soundPath,
    this.recurrence = RecurrenceType.once,
    List<int>? weekdays,
  }) : weekdays = weekdays ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'dateTime': dateTime.toIso8601String(),
        'soundPath': soundPath,
        'recurrence': recurrence.name,
        'weekdays': weekdays,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) {
    try {
      return Appointment(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        dateTime: DateTime.tryParse((j['dateTime'] as String?) ?? '') ??
            DateTime.now(),
        soundPath: j['soundPath'] as String?,
        recurrence: RecurrenceType.values.firstWhere(
          (e) => e.name == (j['recurrence'] ?? 'once'),
          orElse: () => RecurrenceType.once,
        ),
        weekdays: (j['weekdays'] as List?)?.whereType<int>().toList() ?? [],
      );
    } catch (_) {
      return Appointment(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'موعد',
        note: '',
        dateTime: DateTime.now(),
      );
    }
  }

  String recurrenceLabel() {
    try {
      switch (recurrence) {
        case RecurrenceType.once:
          return DateFormat('EEEE d MMM - hh:mm a').format(dateTime);
        case RecurrenceType.daily:
          return 'كل يوم - ${DateFormat('hh:mm a').format(dateTime)}';
        case RecurrenceType.weekly:
          if (weekdays.isEmpty) return 'أيام محددة';
          final days = weekDaysOrder
              .where((w) => weekdays.contains(w))
              .map(weekdayNameAr)
              .join(' • ');
          return '$days - ${DateFormat('hh:mm a').format(dateTime)}';
      }
    } catch (_) {
      return '';
    }
  }
}

class StudySession {
  final DateTime date;
  final int minutes;
  StudySession({required this.date, required this.minutes});

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'minutes': minutes};

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        date: DateTime.tryParse((j['date'] as String?) ?? '') ??
            DateTime.now(),
        minutes: (j['minutes'] as int?) ?? 0,
      );
}

class PomodoroSettings {
  int studyMinutes;
  int breakMinutes;
  String? studySoundPath;
  String? breakSoundPath;

  PomodoroSettings({
    this.studyMinutes = 25,
    this.breakMinutes = 5,
    this.studySoundPath,
    this.breakSoundPath,
  });

  Map<String, dynamic> toJson() => {
        'studyMinutes': studyMinutes,
        'breakMinutes': breakMinutes,
        'studySoundPath': studySoundPath,
        'breakSoundPath': breakSoundPath,
      };

  factory PomodoroSettings.fromJson(Map<String, dynamic> j) =>
      PomodoroSettings(
        studyMinutes: (j['studyMinutes'] as int?) ?? 25,
        breakMinutes: (j['breakMinutes'] as int?) ?? 5,
        studySoundPath: j['studySoundPath'] as String?,
        breakSoundPath: j['breakSoundPath'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════
//  Alarm Service - آمن تماماً
// ═══════════════════════════════════════════════════════════════
class AlarmService {
  AlarmService._();
  static final AlarmService I = AlarmService._();

  DateTime calculateNextTime(Appointment a, {DateTime? from}) {
    final now = from ?? DateTime.now();

    if (a.recurrence == RecurrenceType.once) return a.dateTime;

    final hour = a.dateTime.hour;
    final minute = a.dateTime.minute;

    if (a.recurrence == RecurrenceType.daily) {
      var candidate = DateTime(now.year, now.month, now.day, hour, minute, 0);
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    if (a.weekdays.isEmpty) return a.dateTime;
    for (int i = 0; i < 8; i++) {
      final checkDate = now.add(Duration(days: i));
      if (a.weekdays.contains(checkDate.weekday)) {
        final candidate = DateTime(
          checkDate.year,
          checkDate.month,
          checkDate.day,
          hour,
          minute,
          0,
        );
        if (candidate.isAfter(now)) return candidate;
      }
    }
    return now.add(const Duration(days: 7));
  }

  Future<void> schedule(Appointment a) async {
    try {
      final alarmId = generateAlarmId(a.id);
      final nextTime = calculateNextTime(a);

      if (nextTime.isBefore(DateTime.now()) &&
          a.recurrence == RecurrenceType.once) {
        return;
      }

      // ⚠️ ملاحظة: نستخدم صوت من النظام (silent audio مش هيتشغل هنا)
      // الصوت الحقيقي بيتشغل من AlarmScreen عبر audioplayers
      String soundPath;
      if (a.soundPath != null && File(a.soundPath!).existsSync()) {
        soundPath = a.soundPath!;
      } else {
        soundPath = kSystemAlarmSound;
      }

      final settings = AlarmSettings(
        id: alarmId,
        dateTime: nextTime,
        assetAudioPath: soundPath,
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        // ✅ السطر المطلوب لحل خطأ البناء
        volumeSettings: VolumeSettings.fade(
          volume: 1.0,
          fadeDuration: const Duration(seconds: 3),
          volumeEnforced: false,
        ),
        notificationSettings: NotificationSettings(
          title: '⏰ ${a.title}',
          body: a.note.isEmpty ? 'اضغط لإيقاف المنبه' : a.note,
          stopButton: 'إيقاف',
        ),
      );

      await Alarm.set(alarmSettings: settings);
      debugPrint('✅ Alarm scheduled: ${a.title} at $nextTime');
    } catch (e) {
      debugPrint('🔴 Alarm.schedule error: $e');
    }
  }

  Future<void> cancel(String appointmentId) async {
    try {
      final alarmId = generateAlarmId(appointmentId);
      await Alarm.stop(alarmId);
    } catch (e) {
      debugPrint('🔴 Alarm.cancel error: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await Alarm.stopAll();
    } catch (e) {
      debugPrint('🔴 Alarm.cancelAll error: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  App State
// ═══════════════════════════════════════════════════════════════
class AppState extends ChangeNotifier {
  // ═══ المفاتيح الجديدة ═══
  static const _kAppts = 'appointments_v6';
  static const _kSessions = 'sessions_v6';
  static const _kDark = 'dark_mode_v6';
  static const _kPomodoro = 'pomodoro_settings_v6';

  // ═══ المفاتيح القديمة (للاسترجاع) ═══
  static const List<String> _oldApptsKeys = [
    'appointments',
    'appointments_v1',
    'appointments_v2',
    'appointments_v3',
    'appointments_v4',
    'appointments_v5',
  ];
  static const List<String> _oldSessionsKeys = [
    'sessions',
    'sessions_v1',
    'sessions_v2',
    'sessions_v3',
    'sessions_v4',
    'sessions_v5',
  ];
  static const List<String> _oldDarkKeys = [
    'dark_mode',
    'dark_mode_v1',
    'dark_mode_v2',
    'dark_mode_v3',
    'dark_mode_v4',
    'dark_mode_v5',
  ];
  static const List<String> _oldPomodoroKeys = [
    'pomodoro_settings',
    'pomodoro_settings_v1',
    'pomodoro_settings_v2',
    'pomodoro_settings_v3',
    'pomodoro_settings_v4',
    'pomodoro_settings_v5',
  ];

  final List<Appointment> appointments = [];
  final List<StudySession> sessions = [];
  PomodoroSettings pomodoro = PomodoroSettings();
  bool isDark = false;
  bool loaded = false;

  StreamSubscription<AlarmSettings>? _alarmSub;

  // ═══ Init with Migration ═══
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // ═══ الوضع الليلي ═══
      isDark = sp.getBool(_kDark) ?? false;
      if (!sp.containsKey(_kDark)) {
        for (final oldKey in _oldDarkKeys) {
          if (sp.containsKey(oldKey)) {
            isDark = sp.getBool(oldKey) ?? false;
            await sp.setBool(_kDark, isDark);
            debugPrint('✅ Migrated dark_mode from $oldKey');
            break;
          }
        }
      }

      // ═══ المواعيد ═══
      String? aRaw = sp.getString(_kAppts);
      String? usedKey;

      if (aRaw == null || aRaw.isEmpty) {
        for (final oldKey in _oldApptsKeys) {
          final old = sp.getString(oldKey);
          if (old != null && old.isNotEmpty) {
            aRaw = old;
            usedKey = oldKey;
            break;
          }
        }
      }

      if (aRaw != null && aRaw.isNotEmpty) {
        try {
          final List list = jsonDecode(aRaw) as List;
          appointments.clear();
          appointments.addAll(
            list.whereType<Map<String, dynamic>>().map(Appointment.fromJson),
          );
          // احفظ بالشكل الجديد
          await _persistAppts();
          if (usedKey != null) {
            debugPrint('✅ Migrated appointments from $usedKey');
          }
        } catch (e) {
          debugPrint('🔴 Load appointments error: $e');
        }
      }

      // ═══ الجلسات ═══
      String? sRaw = sp.getString(_kSessions);
      String? usedSKey;

      if (sRaw == null || sRaw.isEmpty) {
        for (final oldKey in _oldSessionsKeys) {
          final old = sp.getString(oldKey);
          if (old != null && old.isNotEmpty) {
            sRaw = old;
            usedSKey = oldKey;
            break;
          }
        }
      }

      if (sRaw != null && sRaw.isNotEmpty) {
        try {
          final List list = jsonDecode(sRaw) as List;
          sessions.clear();
          sessions.addAll(
            list
                .whereType<Map<String, dynamic>>()
                .map(StudySession.fromJson),
          );
          await _persistSessions();
          if (usedSKey != null) {
            debugPrint('✅ Migrated sessions from $usedSKey');
          }
        } catch (e) {
          debugPrint('🔴 Load sessions error: $e');
        }
      }

      // ═══ إعدادات البومودورو ═══
      String? pRaw = sp.getString(_kPomodoro);
      String? usedPKey;

      if (pRaw == null || pRaw.isEmpty) {
        for (final oldKey in _oldPomodoroKeys) {
          final old = sp.getString(oldKey);
          if (old != null && old.isNotEmpty) {
            pRaw = old;
            usedPKey = oldKey;
            break;
          }
        }
      }

      if (pRaw != null && pRaw.isNotEmpty) {
        try {
          pomodoro = PomodoroSettings.fromJson(
            jsonDecode(pRaw) as Map<String, dynamic>,
          );
          await _persistPomodoro();
          if (usedPKey != null) {
            debugPrint('✅ Migrated pomodoro from $usedPKey');
          }
        } catch (e) {
          debugPrint('🔴 Load pomodoro error: $e');
        }
      }

      // ═══ الاستماع لأحداث المنبه ═══
      _alarmSub = Alarm.ringStream.stream.listen(
        _onAlarmRing,
        onError: (e) => debugPrint('🔴 ringStream error: $e'),
      );

      // ═══ إعادة جدولة المواعيد القادمة ═══
      for (final a in appointments) {
        if (a.recurrence != RecurrenceType.once ||
            a.dateTime.isAfter(DateTime.now())) {
          await AlarmService.I.schedule(a);
        }
      }
    } catch (e) {
      debugPrint('🔴 AppState.init error: $e');
    }

    loaded = true;
    notifyListeners();
  }

  void _onAlarmRing(AlarmSettings settings) {
    try {
      final appt = appointments.firstWhere(
        (a) => generateAlarmId(a.id) == settings.id,
        orElse: () => Appointment(
          id: settings.id.toString(),
          title: 'موعد',
          note: '',
          dateTime: DateTime.now(),
        ),
      );

      navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmScreen(appointment: appt),
        ),
      );

      if (appt.recurrence != RecurrenceType.once) {
        Future.delayed(const Duration(seconds: 3), () {
          if (appointments.any((x) => x.id == appt.id)) {
            AlarmService.I.schedule(appt);
          }
        });
      }
    } catch (e) {
      debugPrint('🔴 _onAlarmRing error: $e');
    }
  }

  // ═══ Persist ═══
  Future<void> _persistAppts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kAppts,
        jsonEncode(appointments.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('🔴 _persistAppts error: $e');
    }
  }

  Future<void> _persistSessions() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kSessions,
        jsonEncode(sessions.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('🔴 _persistSessions error: $e');
    }
  }

  Future<void> _persistPomodoro() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPomodoro, jsonEncode(pomodoro.toJson()));
    } catch (e) {
      debugPrint('🔴 _persistPomodoro error: $e');
    }
  }

  Future<void> updatePomodoro(PomodoroSettings s) async {
    pomodoro = s;
    await _persistPomodoro();
    notifyListeners();
  }

  // ═══ CRUD ═══
  Future<void> addAppointment(Appointment a) async {
    appointments.add(a);
    appointments.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    await _persistAppts();
    await AlarmService.I.schedule(a);
    notifyListeners();
  }

  Future<void> updateAppointment(Appointment a) async {
    final i = appointments.indexWhere((x) => x.id == a.id);
    if (i == -1) return;
    await AlarmService.I.cancel(a.id);
    appointments[i] = a;
    appointments.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    await _persistAppts();
    await AlarmService.I.schedule(a);
    notifyListeners();
  }

  Future<void> deleteAppointment(String id) async {
    appointments.removeWhere((x) => x.id == id);
    await AlarmService.I.cancel(id);
    await _persistAppts();
    notifyListeners();
  }

  Future<void> clearAppointments() async {
    final ids = appointments.map((a) => a.id).toList();
    for (final id in ids) {
      await AlarmService.I.cancel(id);
    }
    appointments.clear();
    await _persistAppts();
    notifyListeners();
  }

  Future<void> clearAll() async {
    try {
      appointments.clear();
      sessions.clear();
      pomodoro = PomodoroSettings();
      await AlarmService.I.cancelAll();
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kAppts);
      await sp.remove(_kSessions);
      await sp.remove(_kPomodoro);
    } catch (e) {
      debugPrint('🔴 clearAll error: $e');
    }
    notifyListeners();
  }

  Future<void> toggleDark() async {
    isDark = !isDark;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kDark, isDark);
    } catch (e) {
      debugPrint('🔴 toggleDark error: $e');
    }
    notifyListeners();
  }

  Future<void> addSession(int minutes) async {
    sessions.add(StudySession(date: DateTime.now(), minutes: minutes));
    await _persistSessions();
    notifyListeners();
  }

  @override
  void dispose() {
    _alarmSub?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
//  App Root
// ═══════════════════════════════════════════════════════════════
class MawaidApp extends StatelessWidget {
  const MawaidApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.watch<AppState>().isDark;
    return MaterialApp(
      title: 'مواعيد',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Home Screen
// ═══════════════════════════════════════════════════════════════
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final appts = state.appointments;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواعيدي',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'بومودورو',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PomodoroScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'الإحصائيات',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          if (appts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: 'مسح كل المواعيد',
              onPressed: () => _confirmDeleteAll(context),
            ),
        ],
      ),
      body: !state.loaded
          ? const Center(child: CircularProgressIndicator())
          : appts.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: appts.length,
                  itemBuilder: (_, i) => _appointmentCard(context, appts[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AddAppointmentScreen())),
        icon: const Icon(Icons.add_alarm),
        label: const Text('إضافة موعد'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.teal.withOpacity(0.15),
              ),
              child: const Icon(Icons.alarm_add, size: 80, color: Colors.teal),
            ),
            const SizedBox(height: 24),
            const Text('مفيش مواعيد لسه',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'اضغط على زرار "إضافة موعد" عشان تبدأ',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appointmentCard(BuildContext context, Appointment a) {
    final isRecurring = a.recurrence != RecurrenceType.once;
    final soon = a.dateTime.difference(DateTime.now()).inMinutes;

    IconData icon;
    Color circleColor;
    if (isRecurring) {
      icon = Icons.repeat;
      circleColor = Colors.blue;
    } else if (soon < 0) {
      icon = Icons.alarm_off;
      circleColor = Colors.grey;
    } else if (soon < 60) {
      icon = Icons.alarm;
      circleColor = Colors.red;
    } else {
      icon = Icons.alarm;
      circleColor = Colors.teal;
    }

    return Dismissible(
      key: ValueKey(a.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('حذف',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            SizedBox(width: 8),
            Icon(Icons.delete, color: Colors.white, size: 32),
          ],
        ),
      ),
      confirmDismiss: (_) => _askDelete(context, a),
      onDismissed: (_) async {
        await context.read<AppState>().deleteAppointment(a.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حذف "${a.title}" ✅')),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: circleColor,
                  radius: 26,
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                title: Text(
                  a.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(a.recurrenceLabel(),
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                      if (a.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(a.note,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddAppointmentScreen(existing: a),
                        ),
                      ),
                      icon: const Icon(Icons.edit,
                          color: Colors.blue, size: 20),
                      label: const Text('تعديل',
                          style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Container(
                      width: 1, height: 24, color: Colors.grey.shade300),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        final ok = await _askDelete(context, a);
                        if (ok && context.mounted) {
                          await context
                              .read<AppState>()
                              .deleteAppointment(a.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('تم حذف "${a.title}" ✅')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete,
                          color: Colors.red, size: 20),
                      label: const Text('حذف',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _askDelete(BuildContext context, Appointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الموعد'),
        content: Text('متأكد إنك عايز تحذف "${a.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final state = context.read<AppState>();
    final count = state.appointments.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح كل المواعيد'),
        content: Text('متأكد إنك عايز تمسح كل المواعيد ($count)؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('مسح الكل', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().clearAppointments();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم مسح كل المواعيد ✅')),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Add / Edit Appointment Screen
// ═══════════════════════════════════════════════════════════════
class AddAppointmentScreen extends StatefulWidget {
  final Appointment? existing;
  const AddAppointmentScreen({super.key, this.existing});

  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(minutes: 5));
  TimeOfDay _time = TimeOfDay.now();
  String? _soundPath;
  RecurrenceType _recurrence = RecurrenceType.once;
  Set<int> _selectedWeekdays = {};

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _titleCtrl.text = e.title;
      _noteCtrl.text = e.note;
      _date = e.dateTime;
      _time = TimeOfDay.fromDateTime(e.dateTime);
      _soundPath = e.soundPath;
      _recurrence = e.recurrence;
      _selectedWeekdays = e.weekdays.toSet();
    } else {
      final d = DateTime.now().add(const Duration(minutes: 5));
      _date = d;
      _time = TimeOfDay.fromDateTime(d);
      _selectedWeekdays = {d.weekday};
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    try {
      final d = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );
      if (d != null) setState(() => _date = d);
    } catch (e) {
      debugPrint('🔴 _pickDate error: $e');
    }
  }

  Future<void> _pickTime() async {
    try {
      final t = await showTimePicker(context: context, initialTime: _time);
      if (t != null) setState(() => _time = t);
    } catch (e) {
      debugPrint('🔴 _pickTime error: $e');
    }
  }

  Future<void> _pickSound() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (r == null || r.files.single.path == null) return;
      final src = File(r.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final ext = r.files.single.extension ?? 'mp3';
      final dest = File(
          '${dir.path}/alarm_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await src.copy(dest.path);
      if (mounted) {
        setState(() => _soundPath = dest.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اختيار الصوت ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الملف: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('اكتب اسم الموعد');
      return;
    }

    final dt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    if (_recurrence == RecurrenceType.once && dt.isBefore(DateTime.now())) {
      _snack('الوقت ده فات! اختار وقت في المستقبل');
      return;
    }

    if (_recurrence == RecurrenceType.weekly && _selectedWeekdays.isEmpty) {
      _snack('اختار يوم واحد على الأقل من الأسبوع');
      return;
    }

    DateTime savedDate = dt;
    if (_recurrence != RecurrenceType.once && dt.isBefore(DateTime.now())) {
      savedDate = dt.add(const Duration(days: 1));
    }

    final state = context.read<AppState>();
    if (widget.existing == null) {
      final a = Appointment(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        note: _noteCtrl.text.trim(),
        dateTime: savedDate,
        soundPath: _soundPath,
        recurrence: _recurrence,
        weekdays: _selectedWeekdays.toList(),
      );
      await state.addAppointment(a);
    } else {
      final a = widget.existing!;
      a.title = title;
      a.note = _noteCtrl.text.trim();
      a.dateTime = savedDate;
      a.soundPath = _soundPath;
      a.recurrence = _recurrence;
      a.weekdays = _selectedWeekdays.toList();
      await state.updateAppointment(a);
    }

    if (mounted) {
      _snack(widget.existing == null
          ? 'تم حفظ الموعد ✅'
          : 'تم تعديل الموعد ✅');
      Navigator.pop(context);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'تعديل موعد' : 'موعد جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الموعد',
              hintText: 'مثال: مذاكرة رياضيات',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.repeat, color: Colors.teal),
              SizedBox(width: 8),
              Text('التكرار',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('مرة واحدة'),
                avatar: const Icon(Icons.event, size: 18),
                selected: _recurrence == RecurrenceType.once,
                onSelected: (_) =>
                    setState(() => _recurrence = RecurrenceType.once),
                selectedColor: Colors.teal.shade200,
              ),
              ChoiceChip(
                label: const Text('كل يوم'),
                avatar: const Icon(Icons.repeat, size: 18),
                selected: _recurrence == RecurrenceType.daily,
                onSelected: (_) =>
                    setState(() => _recurrence = RecurrenceType.daily),
                selectedColor: Colors.teal.shade200,
              ),
              ChoiceChip(
                label: const Text('أيام محددة'),
                avatar: const Icon(Icons.calendar_month, size: 18),
                selected: _recurrence == RecurrenceType.weekly,
                onSelected: (_) =>
                    setState(() => _recurrence = RecurrenceType.weekly),
                selectedColor: Colors.teal.shade200,
              ),
            ],
          ),
          if (_recurrence == RecurrenceType.weekly) ...[
            const SizedBox(height: 16),
            const Text('اختار الأيام:',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: weekDaysOrder.map((w) {
                final selected = _selectedWeekdays.contains(w);
                return FilterChip(
                  label: Text(weekdayNameAr(w)),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedWeekdays.add(w);
                      } else {
                        _selectedWeekdays.remove(w);
                      }
                    });
                  },
                  selectedColor: Colors.teal.shade200,
                  checkmarkColor: Colors.teal.shade900,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          if (_recurrence != RecurrenceType.once)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('الوقت',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          Row(
            children: [
              if (_recurrence == RecurrenceType.once)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('yyyy/MM/dd').format(_date)),
                  ),
                ),
              if (_recurrence == RecurrenceType.once) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(_time.format(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note, color: Colors.teal),
              title: const Text('صوت المنبه'),
              subtitle: Text(
                _soundPath == null
                    ? 'افتراضي (نغمة النظام)'
                    : _soundPath!.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _pickSound,
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              isEdit ? 'حفظ التعديلات' : 'حفظ الموعد',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Alarm Screen - مع تشغيل صوت موثوق
// ═══════════════════════════════════════════════════════════════
class AlarmScreen extends StatefulWidget {
  final Appointment appointment;
  const AlarmScreen({super.key, required this.appointment});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  AudioPlayer? _player;
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startSound());
  }

  Future<void> _startSound() async {
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(1.0);

      final path = widget.appointment.soundPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _player!.play(DeviceFileSource(path));
        debugPrint('✅ Playing custom sound');
        return;
      }

      // احتياطي: صوت النظام
      try {
        await _player!.play(UrlSource(kSystemAlarmSound));
      } catch (_) {
        await _player!.play(UrlSource(kSystemNotifySound));
      }
    } catch (e) {
      debugPrint('🔴 Sound error: $e');
    }
  }

  Future<void> _stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await Alarm.stop(generateAlarmId(widget.appointment.id));
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final timeStr = DateFormat('hh:mm a').format(DateTime.now());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.red.shade900, Colors.black],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.12).animate(
                      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 3,
                        ),
                      ),
                      child: const Icon(Icons.alarm,
                          size: 100, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text('⏰ وقت الموعد',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 20)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      a.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (a.note.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      a.note,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 18),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 80,
                    child: FilledButton.icon(
                      onPressed: _stop,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                      ),
                      icon: const Icon(Icons.stop_circle, size: 38),
                      label: const Text(
                        'إيقاف',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Pomodoro Screen
// ═══════════════════════════════════════════════════════════════
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  final AudioPlayer _player = AudioPlayer();

  int _remaining = 0;
  bool _isStudy = true;
  bool _running = false;
  bool _initialized = false;
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final p = context.read<AppState>().pomodoro;
      _remaining = p.studyMinutes * 60;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 0) {
        _switch();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _pause() {
    _t?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _t?.cancel();
    final p = context.read<AppState>().pomodoro;
    setState(() {
      _running = false;
      _isStudy = true;
      _remaining = p.studyMinutes * 60;
    });
  }

  Future<void> _playSound(String? path) async {
    try {
      if (path != null && File(path).existsSync()) {
        await _player.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Sound error: $e');
    }
  }

  Future<void> _switch() async {
    _t?.cancel();
    final p = context.read<AppState>().pomodoro;

    if (_isStudy) {
      await context.read<AppState>().addSession(p.studyMinutes);
      await _playSound(p.studySoundPath);
    } else {
      await _playSound(p.breakSoundPath);
    }

    if (!mounted) return;
    setState(() {
      _isStudy = !_isStudy;
      _remaining = (_isStudy ? p.studyMinutes : p.breakMinutes) * 60;
      _running = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isStudy ? '📚 ابدأ المذاكرة!' : '☕ وقت الراحة!'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PomodoroSettingsScreen()),
    );
    if (mounted) {
      final p = context.read<AppState>().pomodoro;
      if (!_running) {
        setState(() {
          _isStudy = true;
          _remaining = p.studyMinutes * 60;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().pomodoro;
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    final color = _isStudy ? Colors.teal : Colors.orange;
    final totalSec = (_isStudy ? p.studyMinutes : p.breakMinutes) * 60;
    final progress = totalSec == 0 ? 0.0 : 1 - (_remaining / totalSec);

    return Scaffold(
      appBar: AppBar(
        title: const Text('بومودورو'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'إعدادات البومودورو',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isStudy ? '📚 وقت المذاكرة' : '☕ وقت الراحة',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              '${p.studyMinutes} دقيقة مذاكرة • ${p.breakMinutes} دقيقة راحة',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$m:$s',
                        style: TextStyle(
                          fontSize: 62,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isStudy ? 'مذاكرة' : 'راحة',
                        style: TextStyle(
                          fontSize: 16,
                          color: color.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _pause : _start,
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  label: Text(_running ? 'إيقاف مؤقت' : 'ابدأ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size(150, 56),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, 56),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Pomodoro Settings Screen
// ═══════════════════════════════════════════════════════════════
class PomodoroSettingsScreen extends StatefulWidget {
  const PomodoroSettingsScreen({super.key});

  @override
  State<PomodoroSettingsScreen> createState() =>
      _PomodoroSettingsScreenState();
}

class _PomodoroSettingsScreenState extends State<PomodoroSettingsScreen> {
  late int _studyMin;
  late int _breakMin;
  String? _studySoundPath;
  String? _breakSoundPath;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().pomodoro;
    _studyMin = p.studyMinutes;
    _breakMin = p.breakMinutes;
    _studySoundPath = p.studySoundPath;
    _breakSoundPath = p.breakSoundPath;
  }

  Future<void> _pickSound({required bool isStudy}) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (r == null || r.files.single.path == null) return;
      final src = File(r.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final ext = r.files.single.extension ?? 'mp3';
      final prefix = isStudy ? 'study_end' : 'break_end';
      final dest = File(
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await src.copy(dest.path);
      setState(() {
        if (isStudy) {
          _studySoundPath = dest.path;
        } else {
          _breakSoundPath = dest.path;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isStudy
                  ? 'تم اختيار صوت المذاكرة ✅'
                  : 'تم اختيار صوت الراحة ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الملف: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_studyMin < 1 || _studyMin > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('وقت المذاكرة لازم يكون بين 1 و 180 دقيقة')),
      );
      return;
    }
    if (_breakMin < 1 || _breakMin > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('وقت الراحة لازم يكون بين 1 و 60 دقيقة')),
      );
      return;
    }
    final s = PomodoroSettings(
      studyMinutes: _studyMin,
      breakMinutes: _breakMin,
      studySoundPath: _studySoundPath,
      breakSoundPath: _breakSoundPath,
    );
    await context.read<AppState>().updatePomodoro(s);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات ✅')),
      );
      Navigator.pop(context);
    }
  }

  Widget _numberControl({
    required String label,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _roundButton(
                  icon: Icons.remove, color: color, onTap: onMinus),
              Column(
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const Text('دقيقة', style: TextStyle(fontSize: 12)),
                ],
              ),
              _roundButton(icon: Icons.add, color: color, onTap: onPlus),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات البومودورو')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _numberControl(
            label: '📚 وقت المذاكرة',
            value: _studyMin,
            color: Colors.teal,
            onMinus: () => setState(() {
              if (_studyMin > 1) _studyMin--;
            }),
            onPlus: () => setState(() {
              if (_studyMin < 180) _studyMin++;
            }),
          ),
          const SizedBox(height: 12),
          _numberControl(
            label: '☕ وقت الراحة',
            value: _breakMin,
            color: Colors.orange,
            onMinus: () => setState(() {
              if (_breakMin > 1) _breakMin--;
            }),
            onPlus: () => setState(() {
              if (_breakMin < 60) _breakMin++;
            }),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('🔔 أصوات التنبيه',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book, color: Colors.teal),
              title: const Text('صوت نهاية المذاكرة'),
              subtitle: Text(
                _studySoundPath == null
                    ? 'افتراضي'
                    : _studySoundPath!.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () => _pickSound(isStudy: true),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.local_cafe, color: Colors.orange),
              title: const Text('صوت نهاية الراحة'),
              subtitle: Text(
                _breakSoundPath == null
                    ? 'افتراضي'
                    : _breakSoundPath!.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () => _pickSound(isStudy: false),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Stats Screen
// ═══════════════════════════════════════════════════════════════
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().sessions;
    final totalMin = s.fold<int>(0, (a, b) => a + b.minutes);
    final today = DateTime.now();
    final todayMin = s
        .where((x) =>
            x.date.year == today.year &&
            x.date.month == today.month &&
            x.date.day == today.day)
        .fold<int>(0, (a, b) => a + b.minutes);

    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard('اليوم', '$todayMin دقيقة', Colors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard('إجمالي', '$totalMin دقيقة', Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statCard('عدد الجلسات', '${s.length}', Colors.orange),
          const SizedBox(height: 24),
          const Text('آخر الجلسات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          if (s.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('مفيش جلسات لسه',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...s.reversed.take(20).map((x) => ListTile(
                  leading:
                      const Icon(Icons.check_circle, color: Colors.teal),
                  title: Text('${x.minutes} دقيقة'),
                  subtitle: Text(
                      DateFormat('yyyy/MM/dd - hh:mm a').format(x.date)),
                )),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color c) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: c)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════
//  Settings Screen
// ═══════════════════════════════════════════════════════════════
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('الوضع الليلي'),
            value: state.isDark,
            onChanged: (_) => context.read<AppState>().toggleDark(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('إعدادات البومودورو'),
            subtitle: Text(
                '${state.pomodoro.studyMinutes} دقيقة مذاكرة • ${state.pomodoro.breakMinutes} دقيقة راحة'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PomodoroSettingsScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('مسح كل البيانات',
                style: TextStyle(color: Colors.red)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('مسح البيانات'),
                  content:
                      const Text('هيتم مسح كل المواعيد والإحصائيات. متأكد؟'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('مسح',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok == true) {
                await context.read<AppState>().clearAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم مسح البيانات ✅')),
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

// ═══════════════════════════════════════════════════════════════
//  About Screen
// ═══════════════════════════════════════════════════════════════
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عن التطبيق')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.alarm, size: 100, color: Colors.teal),
              SizedBox(height: 24),
              Text('تطبيق مواعيد',
                  style:
                      TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('منبه المذاكرة والبومودورو',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              SizedBox(height: 32),
              Divider(),
              SizedBox(height: 16),
              Text('تطوير',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
              SizedBox(height: 8),
              Text('المهندس يوسف أحمد مصطفى',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal)),
              SizedBox(height: 8),
              Text('الإصدار 1.2.0',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}