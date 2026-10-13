// ═══════════════════════════════════════════════════════════════
//  mawaid - تطبيق مواعيد ومنبه المذاكرة
//  المهندس يوسف أحمد مصطفى
//  نسخة متكاملة: حلقة بومودورو مستمرة + تجربة الصوت + تحدي الصحيان
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
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
//  Enums
// ═══════════════════════════════════════════════════════════════
enum RecurrenceType { once, daily, weekly }

enum AnswerType { text, number }

enum PomodoroPhase {
  idle, // قبل البدء
  studying, // وقت المذاكرة شغال
  studyDone, // خلصت المذاكرة - الصوت شغال
  breaking, // وقت الراحة شغال
  breakDone, // خلصت الراحة - الصوت شغال
  paused, // إيقاف مؤقت
  finished, // إيقاف نهائي
}

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

class WakeChallenge {
  final String id;
  String name;
  DateTime dateTime;
  RecurrenceType recurrence;
  List<int> weekdays;
  String question;
  String answer;
  AnswerType answerType;
  String? soundPath;
  bool enabled;

  WakeChallenge({
    required this.id,
    required this.name,
    required this.dateTime,
    this.recurrence = RecurrenceType.once,
    List<int>? weekdays,
    required this.question,
    required this.answer,
    this.answerType = AnswerType.text,
    this.soundPath,
    this.enabled = true,
  }) : weekdays = weekdays ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dateTime': dateTime.toIso8601String(),
        'recurrence': recurrence.name,
        'weekdays': weekdays,
        'question': question,
        'answer': answer,
        'answerType': answerType.name,
        'soundPath': soundPath,
        'enabled': enabled,
      };

  factory WakeChallenge.fromJson(Map<String, dynamic> j) {
    try {
      return WakeChallenge(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        dateTime: DateTime.tryParse((j['dateTime'] as String?) ?? '') ??
            DateTime.now(),
        recurrence: RecurrenceType.values.firstWhere(
          (e) => e.name == (j['recurrence'] ?? 'once'),
          orElse: () => RecurrenceType.once,
        ),
        weekdays: (j['weekdays'] as List?)?.whereType<int>().toList() ?? [],
        question: (j['question'] as String?) ?? '',
        answer: (j['answer'] as String?) ?? '',
        answerType: AnswerType.values.firstWhere(
          (e) => e.name == (j['answerType'] ?? 'text'),
          orElse: () => AnswerType.text,
        ),
        soundPath: j['soundPath'] as String?,
        enabled: (j['enabled'] as bool?) ?? true,
      );
    } catch (_) {
      return WakeChallenge(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: 'تحدي جديد',
        dateTime: DateTime.now(),
        question: '1 + 1 = ?',
        answer: '2',
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

  DateTime calculateNextTimeForChallenge(WakeChallenge c, {DateTime? from}) {
    final now = from ?? DateTime.now();

    if (c.recurrence == RecurrenceType.once) return c.dateTime;

    final hour = c.dateTime.hour;
    final minute = c.dateTime.minute;

    if (c.recurrence == RecurrenceType.daily) {
      var candidate = DateTime(now.year, now.month, now.day, hour, minute, 0);
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    if (c.weekdays.isEmpty) return c.dateTime;
    for (int i = 0; i < 8; i++) {
      final checkDate = now.add(Duration(days: i));
      if (c.weekdays.contains(checkDate.weekday)) {
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
        loopAudio: false,
        vibrate: true,
        androidFullScreenIntent: true,
        volumeSettings: const VolumeSettings.fixed(
          volume: 0.0,
          volumeEnforced: true,
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

  Future<void> scheduleWakeChallenge(WakeChallenge c) async {
    try {
      if (!c.enabled) {
        await cancelWakeChallenge(c.id);
        return;
      }

      final alarmId = generateAlarmId(c.id);
      final nextTime = calculateNextTimeForChallenge(c);

      if (nextTime.isBefore(DateTime.now()) &&
          c.recurrence == RecurrenceType.once) {
        return;
      }

      String soundPath;
      if (c.soundPath != null && File(c.soundPath!).existsSync()) {
        soundPath = c.soundPath!;
      } else {
        soundPath = kSystemAlarmSound;
      }

      final settings = AlarmSettings(
        id: alarmId,
        dateTime: nextTime,
        assetAudioPath: soundPath,
        loopAudio: false,
        vibrate: true,
        androidFullScreenIntent: true,
        volumeSettings: const VolumeSettings.fixed(
          volume: 0.0,
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: '⏰ ${c.name}',
          body: 'اضغط لحل السؤال والاستيقاظ',
          stopButton: 'افتح',
        ),
      );

      await Alarm.set(alarmSettings: settings);
      debugPrint('✅ Wake challenge scheduled: ${c.name} at $nextTime');
    } catch (e) {
      debugPrint('🔴 AlarmService.scheduleWakeChallenge error: $e');
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

  Future<void> cancelWakeChallenge(String challengeId) async {
    try {
      final alarmId = generateAlarmId(challengeId);
      await Alarm.stop(alarmId);
    } catch (e) {
      debugPrint('🔴 AlarmService.cancelWakeChallenge error: $e');
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
  static const _kAppts = 'appointments_v6';
  static const _kSessions = 'sessions_v6';
  static const _kDark = 'dark_mode_v6';
  static const _kPomodoro = 'pomodoro_settings_v6';
  static const _kWakeChallenges = 'wake_challenges_v1';

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
  final List<WakeChallenge> wakeChallenges = [];
  PomodoroSettings pomodoro = PomodoroSettings();
  bool isDark = false;
  bool loaded = false;

  StreamSubscription<AlarmSettings>? _alarmSub;

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

      // ═══ تحديات الصحيان ═══
      String? wRaw = sp.getString(_kWakeChallenges);
      if (wRaw != null && wRaw.isNotEmpty) {
        try {
          final List list = jsonDecode(wRaw) as List;
          wakeChallenges.clear();
          wakeChallenges.addAll(
            list
                .whereType<Map<String, dynamic>>()
                .map(WakeChallenge.fromJson),
          );
        } catch (e) {
          debugPrint('🔴 Load wake challenges error: $e');
        }
      }

      // ═══ الاستماع لأحداث المنبه ═══
      _alarmSub = Alarm.ringStream.stream.listen(
        _onAlarmRing,
        onError: (e) => debugPrint('🔴 ringStream error: $e'),
      );

      // ═══ إعادة جدولة المواعيد وتحديات الصحيان ═══
      for (final a in appointments) {
        if (a.recurrence != RecurrenceType.once ||
            a.dateTime.isAfter(DateTime.now())) {
          await AlarmService.I.schedule(a);
        }
      }

      for (final c in wakeChallenges) {
        if (c.enabled) {
          if (c.recurrence != RecurrenceType.once ||
              c.dateTime.isAfter(DateTime.now())) {
            await AlarmService.I.scheduleWakeChallenge(c);
          }
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
      // 1. فحص المواعيد
      Appointment? foundAppt;
      for (final a in appointments) {
        if (generateAlarmId(a.id) == settings.id) {
          foundAppt = a;
          break;
        }
      }

      if (foundAppt != null) {
        navKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AlarmScreen(appointment: foundAppt!),
          ),
        );

        if (foundAppt.recurrence != RecurrenceType.once) {
          final apptToReschedule = foundAppt;
          Future.delayed(const Duration(seconds: 3), () {
            if (appointments.any((x) => x.id == apptToReschedule.id)) {
              AlarmService.I.schedule(apptToReschedule);
            }
          });
        }
        return;
      }

      // 2. فحص تحديات الصحيان
      WakeChallenge? foundChallenge;
      for (final c in wakeChallenges) {
        if (generateAlarmId(c.id) == settings.id) {
          foundChallenge = c;
          break;
        }
      }

      if (foundChallenge != null && foundChallenge.enabled) {
        final challengeToReschedule = foundChallenge;
        navKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) =>
                WakeChallengeAlarmScreen(challenge: challengeToReschedule),
          ),
        );

        if (challengeToReschedule.recurrence != RecurrenceType.once) {
          Future.delayed(const Duration(seconds: 3), () {
            if (wakeChallenges
                .any((x) => x.id == challengeToReschedule.id && x.enabled)) {
              AlarmService.I.scheduleWakeChallenge(challengeToReschedule);
            }
          });
        }
        return;
      }

      // إذا لم يتم العثور على أي موعد، شاشة طوارئ
      navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmScreen(
            appointment: Appointment(
              id: settings.id.toString(),
              title: 'منبه',
              note: '',
              dateTime: DateTime.now(),
            ),
          ),
        ),
      );
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

  Future<void> _persistWakeChallenges() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kWakeChallenges,
        jsonEncode(wakeChallenges.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('🔴 _persistWakeChallenges error: $e');
    }
  }

  Future<void> updatePomodoro(PomodoroSettings s) async {
    pomodoro = s;
    await _persistPomodoro();
    notifyListeners();
  }

  // ═══ Appointments CRUD ═══
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

  // ═══ Wake Challenges CRUD ═══
  Future<void> addWakeChallenge(WakeChallenge c) async {
    wakeChallenges.add(c);
    wakeChallenges.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    await _persistWakeChallenges();
    if (c.enabled) {
      await AlarmService.I.scheduleWakeChallenge(c);
    }
    notifyListeners();
  }

  Future<void> updateWakeChallenge(WakeChallenge c) async {
    final i = wakeChallenges.indexWhere((x) => x.id == c.id);
    if (i == -1) return;
    await AlarmService.I.cancelWakeChallenge(c.id);
    wakeChallenges[i] = c;
    wakeChallenges.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    await _persistWakeChallenges();
    if (c.enabled) {
      await AlarmService.I.scheduleWakeChallenge(c);
    }
    notifyListeners();
  }

  Future<void> toggleWakeChallenge(String id, bool enabled) async {
    final i = wakeChallenges.indexWhere((x) => x.id == id);
    if (i == -1) return;
    wakeChallenges[i].enabled = enabled;
    await _persistWakeChallenges();
    if (enabled) {
      await AlarmService.I.scheduleWakeChallenge(wakeChallenges[i]);
    } else {
      await AlarmService.I.cancelWakeChallenge(id);
    }
    notifyListeners();
  }

  Future<void> deleteWakeChallenge(String id) async {
    wakeChallenges.removeWhere((x) => x.id == id);
    await AlarmService.I.cancelWakeChallenge(id);
    await _persistWakeChallenges();
    notifyListeners();
  }

  Future<void> clearWakeChallenges() async {
    for (final c in wakeChallenges) {
      await AlarmService.I.cancelWakeChallenge(c.id);
    }
    wakeChallenges.clear();
    await _persistWakeChallenges();
    notifyListeners();
  }

  // ═══ General CRUD & State ═══
  Future<void> clearAll() async {
    try {
      appointments.clear();
      sessions.clear();
      wakeChallenges.clear();
      pomodoro = PomodoroSettings();
      await AlarmService.I.cancelAll();
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kAppts);
      await sp.remove(_kSessions);
      await sp.remove(_kPomodoro);
      await sp.remove(_kWakeChallenges);
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
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
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
          // جديد: زر تحدي الصحيان في الأول
          IconButton(
            icon: const Icon(Icons.alarm_on),
            tooltip: 'تحدي الصحيان',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WakeChallengeListScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'بومودورو',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PomodoroScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'الإحصائيات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
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
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddAppointmentScreen()),
        ),
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
                color: Colors.teal.withValues(alpha: 0.15),
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
                color: isDark ? Colors.white70 : Colors.black54,
              ),
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
//  ✅ مع زر تجربة الصوت
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

  AudioPlayer? _previewPlayer;
  bool _isPlaying = false;

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
    _stopPreview();
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
      await _stopPreview();
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

  Future<void> _togglePreview() async {
    if (_isPlaying) {
      await _stopPreview();
      return;
    }

    if (_soundPath == null) return;

    try {
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setReleaseMode(ReleaseMode.stop);
      await _previewPlayer!.setVolume(1.0);

      if (File(_soundPath!).existsSync()) {
        await _previewPlayer!.play(DeviceFileSource(_soundPath!));
      } else {
        await _previewPlayer!.play(
          UrlSource(kSystemAlarmSound),
        );
      }

      setState(() => _isPlaying = true);

      _previewPlayer!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (e) {
      debugPrint('Preview error: $e');
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer?.stop();
      await _previewPlayer?.dispose();
      _previewPlayer = null;
    } catch (_) {}
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _save() async {
    await _stopPreview();

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

    if (!mounted) return;
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
          // ═══ كارت الصوت مع زر تجربة الصوت ═══
          Card(
            child: Column(
              children: [
                ListTile(
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
                if (_soundPath != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                                _isPlaying ? Icons.stop : Icons.play_arrow),
                            label: Text(_isPlaying ? 'إيقاف' : 'تجربة الصوت'),
                            onPressed: _togglePreview,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'إزالة الصوت المخصص',
                          onPressed: () {
                            _stopPreview();
                            setState(() => _soundPath = null);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
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
//  Alarm Screen للمواعيد العادية
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
  bool _soundStarted = false;

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
    if (_soundStarted) return;
    _soundStarted = true;

    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(1.0);

      final path = widget.appointment.soundPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _player!.play(DeviceFileSource(path));
        debugPrint('✅ Playing custom sound: $path');
        return;
      }

      try {
        await _player!.play(UrlSource(kSystemAlarmSound));
        debugPrint('✅ Playing system alarm');
      } catch (e) {
        debugPrint('🔴 System alarm failed: $e');
        try {
          await _player!.play(UrlSource(kSystemNotifySound));
        } catch (e2) {
          debugPrint('🔴 Notification sound failed: $e2');
        }
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
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
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
                      color: Colors.white.withValues(alpha: 0.08),
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
//  Pomodoro Screen - حلقة مستمرة لانهائية
// ═══════════════════════════════════════════════════════════════
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  PomodoroPhase _phase = PomodoroPhase.idle;
  int _remaining = 0;
  Timer? _t;
  final AudioPlayer _player = AudioPlayer();
  bool _soundPlaying = false;
  int _completedCycles = 0;
  int _totalStudyMinutes = 0;
  bool _initialized = false;

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

  void _startTimer() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 0) {
        _onTimerEnd();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _onTimerEnd() async {
    _t?.cancel();
    final p = context.read<AppState>().pomodoro;
    final studyMinutes = p.studyMinutes;
    final studySoundPath = p.studySoundPath;
    final breakSoundPath = p.breakSoundPath;

    if (_phase == PomodoroPhase.studying) {
      await context.read<AppState>().addSession(studyMinutes);
      setState(() {
        _phase = PomodoroPhase.studyDone;
        _completedCycles++;
        _totalStudyMinutes += studyMinutes;
      });
      await _playLoopSound(studySoundPath);
    } else if (_phase == PomodoroPhase.breaking) {
      setState(() => _phase = PomodoroPhase.breakDone);
      await _playLoopSound(breakSoundPath);
    }
  }

  Future<void> _playLoopSound(String? soundPath) async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      if (soundPath != null && File(soundPath).existsSync()) {
        await _player.play(DeviceFileSource(soundPath));
      } else {
        try {
          await _player.play(UrlSource(kSystemAlarmSound));
        } catch (_) {
          await _player.play(UrlSource(kSystemNotifySound));
        }
      }
      if (mounted) setState(() => _soundPlaying = true);
    } catch (e) {
      debugPrint('Sound error: $e');
    }
  }

  Future<void> _stopSound() async {
    if (_soundPlaying) {
      try {
        await _player.stop();
      } catch (_) {}
      _soundPlaying = false;
    }

    if (!mounted) return;
    final p = context.read<AppState>().pomodoro;
    final studyMinutes = p.studyMinutes;
    final breakMinutes = p.breakMinutes;

    if (_phase == PomodoroPhase.studyDone) {
      // بدء الراحة تلقائياً
      setState(() {
        _phase = PomodoroPhase.breaking;
        _remaining = breakMinutes * 60;
      });
      _startTimer();
    } else if (_phase == PomodoroPhase.breakDone) {
      // بدء المذاكرة تلقائياً
      setState(() {
        _phase = PomodoroPhase.studying;
        _remaining = studyMinutes * 60;
      });
      _startTimer();
    }
  }

  void _startInitial() {
    final p = context.read<AppState>().pomodoro;
    setState(() {
      _phase = PomodoroPhase.studying;
      _remaining = p.studyMinutes * 60;
    });
    _startTimer();
  }

  void _pause() {
    _t?.cancel();
    setState(() => _phase = PomodoroPhase.paused);
  }

  void _resume() {
    // الرجوع للمذاكرة أو الراحة
    setState(() => _phase = PomodoroPhase.studying);
    _startTimer();
  }

  void _reset() {
    _t?.cancel();
    if (_soundPlaying) {
      _player.stop();
      _soundPlaying = false;
    }
    final p = context.read<AppState>().pomodoro;
    setState(() {
      _phase = PomodoroPhase.idle;
      _remaining = p.studyMinutes * 60;
      _completedCycles = 0;
      _totalStudyMinutes = 0;
    });
  }

  void _finalStop() {
    _t?.cancel();
    if (_soundPlaying) {
      _player.stop();
      _soundPlaying = false;
    }
    setState(() {
      _phase = PomodoroPhase.finished;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PomodoroSettingsScreen()),
    );
    if (mounted) {
      final p = context.read<AppState>().pomodoro;
      if (_phase == PomodoroPhase.idle) {
        setState(() {
          _remaining = p.studyMinutes * 60;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == PomodoroPhase.studyDone) {
      return _buildStudyDoneScreen();
    }
    if (_phase == PomodoroPhase.breakDone) {
      return _buildBreakDoneScreen();
    }
    if (_phase == PomodoroPhase.finished) {
      return _buildFinishedScreen();
    }

    final p = context.watch<AppState>().pomodoro;
    final isBreak = _phase == PomodoroPhase.breaking;
    final isStudying = _phase == PomodoroPhase.studying;
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    final color = isBreak ? Colors.orange : Colors.teal;
    final totalSec = (isBreak ? p.breakMinutes : p.studyMinutes) * 60;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isBreak ? '☕ وقت الراحة' : '📚 وقت المذاكرة',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                '${p.studyMinutes} دقيقة مذاكرة • ${p.breakMinutes} دقيقة راحة',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              if (_completedCycles > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'الدورات المكتملة: $_completedCycles ($_totalStudyMinutes دقيقة)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
              ],
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
                        value: progress.clamp(0.0, 1.0),
                        strokeWidth: 10,
                        backgroundColor: color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$m:$s',
                          style: TextStyle(
                            fontSize: 60,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isBreak ? 'راحة' : 'مذاكرة',
                          style: TextStyle(
                            fontSize: 16,
                            color: color.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              if (_phase == PomodoroPhase.idle) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _startInitial,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('ابدأ'),
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
              ] else if (isStudying || isBreak) ...[
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _pause,
                          icon: const Icon(Icons.pause),
                          label: const Text('إيقاف مؤقت'),
                          style: FilledButton.styleFrom(
                            backgroundColor: color,
                            minimumSize: const Size(150, 56),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _finalStop,
                          icon: const Icon(Icons.stop, color: Colors.red),
                          label: const Text('إيقاف نهائي',
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(130, 56),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else if (_phase == PomodoroPhase.paused) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _resume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('استئناف'),
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        minimumSize: const Size(150, 56),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _finalStop,
                      icon: const Icon(Icons.stop, color: Colors.red),
                      label: const Text('إيقاف نهائي',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        minimumSize: const Size(130, 56),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // شاشة ملء الشاشة برتقالية عند انتهاء المذاكرة
  Widget _buildStudyDoneScreen() {
    return Scaffold(
      backgroundColor: Colors.orange.shade900,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepOrange.shade800, Colors.black],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.notifications_active,
                      size: 80, color: Colors.white),
                ),
                const SizedBox(height: 32),
                const Text(
                  '🎉 خلصت وقت المذاكرة!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'الصوت مستمر، اضغط لإيقاف الصوت وبدء الراحة تلقائياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 72,
                  child: FilledButton.icon(
                    onPressed: _stopSound,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepOrange.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(36),
                      ),
                    ),
                    icon: const Icon(Icons.volume_off, size: 30),
                    label: const Text(
                      '🔇 إيقاف الصوت وبدء الراحة',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _finalStop,
                  child: const Text('إيقاف نهائي للبومودورو',
                      style: TextStyle(color: Colors.white60)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // شاشة ملء الشاشة زرقاء عند انتهاء الراحة
  Widget _buildBreakDoneScreen() {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade800, Colors.black],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.notifications_active,
                      size: 80, color: Colors.white),
                ),
                const SizedBox(height: 32),
                const Text(
                  '☕ خلصت الراحة!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'جاهز لجولة مذاكرة جديدة؟ اضغط لبدء المذاكرة تلقائياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 72,
                  child: FilledButton.icon(
                    onPressed: _stopSound,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.teal.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(36),
                      ),
                    ),
                    icon: const Icon(Icons.volume_off, size: 30),
                    label: const Text(
                      '🔇 إيقاف الصوت وبدء المذاكرة',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _finalStop,
                  child: const Text('إيقاف نهائي للبومودورو',
                      style: TextStyle(color: Colors.white60)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // شاشة الإيقاف النهائي
  Widget _buildFinishedScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('انتهاء الجلسة')),
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
                  shape: BoxShape.circle,
                  color: Colors.teal.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.military_tech,
                    size: 70, color: Colors.teal),
              ),
              const SizedBox(height: 24),
              const Text(
                'عاش يا بطل! 👏',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'أنهيت جلسة البومودورو بنجاح',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 28),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('الدورات المكتملة',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text('$_completedCycles',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal)),
                        ],
                      ),
                      Container(
                          width: 1, height: 50, color: Colors.grey.shade300),
                      Column(
                        children: [
                          const Text('دقائق المذاكرة',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text('$_totalStudyMinutes',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('ابدأ من جديد',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 56),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Pomodoro Settings Screen
//  ✅ مع أزرار معاينة الأصوات
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

  AudioPlayer? _previewPlayer;
  bool _isPlayingStudy = false;
  bool _isPlayingBreak = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().pomodoro;
    _studyMin = p.studyMinutes;
    _breakMin = p.breakMinutes;
    _studySoundPath = p.studySoundPath;
    _breakSoundPath = p.breakSoundPath;
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer?.stop();
      await _previewPlayer?.dispose();
      _previewPlayer = null;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isPlayingStudy = false;
        _isPlayingBreak = false;
      });
    }
  }

  Future<void> _togglePreviewSound({required bool isStudy}) async {
    final path = isStudy ? _studySoundPath : _breakSoundPath;
    final currentlyPlaying = isStudy ? _isPlayingStudy : _isPlayingBreak;

    if (currentlyPlaying) {
      await _stopPreview();
      return;
    }

    await _stopPreview();

    try {
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setReleaseMode(ReleaseMode.stop);
      await _previewPlayer!.setVolume(1.0);

      if (path != null && File(path).existsSync()) {
        await _previewPlayer!.play(DeviceFileSource(path));
      } else {
        await _previewPlayer!.play(UrlSource(kSystemAlarmSound));
      }

      setState(() {
        if (isStudy) {
          _isPlayingStudy = true;
          _isPlayingBreak = false;
        } else {
          _isPlayingBreak = true;
          _isPlayingStudy = false;
        }
      });

      _previewPlayer!.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlayingStudy = false;
            _isPlayingBreak = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Preview error: $e');
      if (mounted) {
        setState(() {
          _isPlayingStudy = false;
          _isPlayingBreak = false;
        });
      }
    }
  }

  Future<void> _pickSound({required bool isStudy}) async {
    try {
      await _stopPreview();
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
    await _stopPreview();
    if (!mounted) return;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات ✅')),
    );
    Navigator.pop(context);
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
          // كارت صوت المذاكرة
          Card(
            child: Column(
              children: [
                ListTile(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(_isPlayingStudy
                              ? Icons.stop
                              : Icons.play_arrow),
                          label: Text(_isPlayingStudy ? 'إيقاف' : 'تجربة الصوت'),
                          onPressed: () =>
                              _togglePreviewSound(isStudy: true),
                        ),
                      ),
                      if (_studySoundPath != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'إعادة للافتراضي',
                          onPressed: () {
                            _stopPreview();
                            setState(() => _studySoundPath = null);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // كارت صوت الراحة
          Card(
            child: Column(
              children: [
                ListTile(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(_isPlayingBreak
                              ? Icons.stop
                              : Icons.play_arrow),
                          label: Text(_isPlayingBreak ? 'إيقاف' : 'تجربة الصوت'),
                          onPressed: () =>
                              _togglePreviewSound(isStudy: false),
                        ),
                      ),
                      if (_breakSoundPath != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'إعادة للافتراضي',
                          onPressed: () {
                            _stopPreview();
                            setState(() => _breakSoundPath = null);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
//  Wake Challenge List Screen (قائمة تحديات الصحيان)
// ═══════════════════════════════════════════════════════════════
class WakeChallengeListScreen extends StatelessWidget {
  const WakeChallengeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final challenges = state.wakeChallenges;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحديات الصحيان',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: challenges.isEmpty
          ? Center(
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
                        color: Colors.red.withValues(alpha: 0.15),
                      ),
                      child: const Icon(Icons.alarm_on,
                          size: 80, color: Colors.red),
                    ),
                    const SizedBox(height: 24),
                    const Text('مفيش تحديات صحيان لسه',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      'اضبط منبه وسؤال مخصص، والمنبه مش هيفصل غير لما تجاوب صح!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: challenges.length,
              itemBuilder: (context, i) {
                final c = challenges[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: CircleAvatar(
                            backgroundColor:
                                c.enabled ? Colors.red.shade700 : Colors.grey,
                            radius: 26,
                            child: const Icon(Icons.wb_sunny,
                                color: Colors.white, size: 26),
                          ),
                          title: Text(
                            c.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
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
                                    Text(c.recurrenceLabel(),
                                        style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.quiz,
                                        size: 14, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'السؤال: ${c.question}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: Switch(
                            value: c.enabled,
                            activeThumbColor: Colors.teal,
                            onChanged: (val) {
                              state.toggleWakeChallenge(c.id, val);
                            },
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
                                    builder: (_) =>
                                        AddWakeChallengeScreen(existing: c),
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
                                width: 1,
                                height: 24,
                                color: Colors.grey.shade300),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('حذف التحدي'),
                                      content: Text(
                                          'متأكد إنك عايز تحذف تحدي "${c.name}"؟'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('إلغاء'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('حذف',
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true && context.mounted) {
                                    await state.deleteWakeChallenge(c.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'تم حذف "${c.name}" ✅')),
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
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddWakeChallengeScreen()),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('إضافة تحدي'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Add / Edit Wake Challenge Screen
// ═══════════════════════════════════════════════════════════════
class AddWakeChallengeScreen extends StatefulWidget {
  final WakeChallenge? existing;
  const AddWakeChallengeScreen({super.key, this.existing});

  @override
  State<AddWakeChallengeScreen> createState() =>
      _AddWakeChallengeScreenState();
}

class _AddWakeChallengeScreenState extends State<AddWakeChallengeScreen> {
  final _nameCtrl = TextEditingController();
  final _questionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  DateTime _date = DateTime.now().add(const Duration(minutes: 5));
  TimeOfDay _time = TimeOfDay.now();
  String? _soundPath;
  RecurrenceType _recurrence = RecurrenceType.daily;
  Set<int> _selectedWeekdays = {};
  AnswerType _answerType = AnswerType.text;

  AudioPlayer? _previewPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _nameCtrl.text = e.name;
      _questionCtrl.text = e.question;
      _answerCtrl.text = e.answer;
      _date = e.dateTime;
      _time = TimeOfDay.fromDateTime(e.dateTime);
      _soundPath = e.soundPath;
      _recurrence = e.recurrence;
      _selectedWeekdays = e.weekdays.toSet();
      _answerType = e.answerType;
    } else {
      final d = DateTime.now().add(const Duration(minutes: 5));
      _date = d;
      _time = TimeOfDay.fromDateTime(d);
      _selectedWeekdays = {d.weekday};
      _questionCtrl.text = '5 + 7 = ?';
      _answerCtrl.text = '12';
      _answerType = AnswerType.number;
    }
  }

  @override
  void dispose() {
    _stopPreview();
    _nameCtrl.dispose();
    _questionCtrl.dispose();
    _answerCtrl.dispose();
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
      await _stopPreview();
      final r = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (r == null || r.files.single.path == null) return;
      final src = File(r.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final ext = r.files.single.extension ?? 'mp3';
      final dest = File(
          '${dir.path}/wake_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await src.copy(dest.path);
      if (mounted) {
        setState(() => _soundPath = dest.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اختيار صوت التحدي ✅')),
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

  Future<void> _togglePreview() async {
    if (_isPlaying) {
      await _stopPreview();
      return;
    }

    if (_soundPath == null) return;

    try {
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setReleaseMode(ReleaseMode.stop);
      await _previewPlayer!.setVolume(1.0);

      if (File(_soundPath!).existsSync()) {
        await _previewPlayer!.play(DeviceFileSource(_soundPath!));
      } else {
        await _previewPlayer!.play(UrlSource(kSystemAlarmSound));
      }

      setState(() => _isPlaying = true);

      _previewPlayer!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (e) {
      debugPrint('Preview error: $e');
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer?.stop();
      await _previewPlayer?.dispose();
      _previewPlayer = null;
    } catch (_) {}
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _save() async {
    await _stopPreview();

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('اكتب اسم التحدي');
      return;
    }

    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      _snack('اكتب سؤال التحدي');
      return;
    }

    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) {
      _snack('اكتب الإجابة الصحيحة');
      return;
    }

    if (_answerType == AnswerType.number && double.tryParse(answer) == null) {
      _snack('نوع الإجابة رقمي، الرجاء كتابة رقم صحيح');
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

    if (!mounted) return;
    final state = context.read<AppState>();
    if (widget.existing == null) {
      final c = WakeChallenge(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        dateTime: savedDate,
        recurrence: _recurrence,
        weekdays: _selectedWeekdays.toList(),
        question: question,
        answer: answer,
        answerType: _answerType,
        soundPath: _soundPath,
        enabled: true,
      );
      await state.addWakeChallenge(c);
    } else {
      final c = widget.existing!;
      c.name = name;
      c.dateTime = savedDate;
      c.recurrence = _recurrence;
      c.weekdays = _selectedWeekdays.toList();
      c.question = question;
      c.answer = answer;
      c.answerType = _answerType;
      c.soundPath = _soundPath;
      await state.updateWakeChallenge(c);
    }

    if (mounted) {
      _snack(widget.existing == null
          ? 'تم حفظ تحدي الصحيان ✅'
          : 'تم تعديل تحدي الصحيان ✅');
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
      appBar: AppBar(title: Text(isEdit ? 'تعديل التحدي' : 'تحدي صحيان جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم التحدي',
              hintText: 'مثال: صحيان الفجر / دوام الصباح',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.alarm),
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
          const SizedBox(height: 16),
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
          const Text('🧠 سؤال الاستيقاظ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _questionCtrl,
            decoration: const InputDecoration(
              labelText: 'السؤال',
              hintText: 'مثال: 5 + 7 = ? أو ما هي عاصمة مصر؟',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.help_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answerCtrl,
            keyboardType: _answerType == AnswerType.number
                ? TextInputType.number
                : TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'الإجابة الصحيحة',
              hintText: 'مثال: 12 أو القاهرة',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('نوع الإجابة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('رقم'),
                selected: _answerType == AnswerType.number,
                onSelected: (_) =>
                    setState(() => _answerType = AnswerType.number),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('نص'),
                selected: _answerType == AnswerType.text,
                onSelected: (_) =>
                    setState(() => _answerType = AnswerType.text),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          // كارت الصوت
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.music_note, color: Colors.teal),
                  title: const Text('صوت المنبه للتحدي'),
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
                if (_soundPath != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                                _isPlaying ? Icons.stop : Icons.play_arrow),
                            label: Text(_isPlaying ? 'إيقاف' : 'تجربة الصوت'),
                            onPressed: _togglePreview,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'إزالة الصوت',
                          onPressed: () {
                            _stopPreview();
                            setState(() => _soundPath = null);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(
              isEdit ? 'حفظ التعديلات' : 'حفظ التحدي',
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
//  Wake Challenge Alarm Screen (شاشة التحدي عند الرنين)
//  ⚠️ لا يفصل الصوت إلا بكتابة الإجابة الصحيحة!
// ═══════════════════════════════════════════════════════════════
class WakeChallengeAlarmScreen extends StatefulWidget {
  final WakeChallenge challenge;
  const WakeChallengeAlarmScreen({super.key, required this.challenge});

  @override
  State<WakeChallengeAlarmScreen> createState() =>
      _WakeChallengeAlarmScreenState();
}

class _WakeChallengeAlarmScreenState extends State<WakeChallengeAlarmScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  final TextEditingController _answerCtrl = TextEditingController();
  AudioPlayer? _player;
  bool _soundStarted = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startSound());
  }

  Future<void> _startSound() async {
    if (_soundStarted) return;
    _soundStarted = true;

    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(1.0);

      final path = widget.challenge.soundPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _player!.play(DeviceFileSource(path));
        return;
      }

      try {
        await _player!.play(UrlSource(kSystemAlarmSound));
      } catch (_) {
        await _player!.play(UrlSource(kSystemNotifySound));
      }
    } catch (e) {
      debugPrint('🔴 WakeChallenge sound error: $e');
    }
  }

  Future<void> _stopSound() async {
    try {
      await _player?.stop();
      await _player?.dispose();
      _player = null;
    } catch (_) {}
  }

  bool _checkAnswer(String userAnswer) {
    final user = userAnswer.trim();
    final correct = widget.challenge.answer.trim();

    if (widget.challenge.answerType == AnswerType.number) {
      final u = double.tryParse(user);
      final c = double.tryParse(correct);
      return u != null && c != null && u == c;
    }

    return user.toLowerCase() == correct.toLowerCase();
  }

  Future<void> _verifyAnswer() async {
    final input = _answerCtrl.text;
    final isCorrect = _checkAnswer(input);

    if (isCorrect) {
      _dismissed = true;
      await _stopSound();
      try {
        await Alarm.stop(generateAlarmId(widget.challenge.id));
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 صح! صباح الخير والأمل'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      HapticFeedback.heavyImpact();
      _answerCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ إجابة غلط، حاول تاني! الصوت مش هيفصل'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopSound();
    _anim.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm a').format(DateTime.now());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_dismissed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ لازم تحل السؤال صح عشان تقفل المنبه!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.15).animate(
                      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.alarm_on,
                          size: 70, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.challenge.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // كارت السؤال
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '🧠 أجب عن السؤال للاستيقاظ وإيقاف الصوت:',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.challenge.question,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // حقل الإجابة
                  TextField(
                    controller: _answerCtrl,
                    keyboardType:
                        widget.challenge.answerType == AnswerType.number
                            ? TextInputType.number
                            : TextInputType.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'اكتب إجابتك هنا',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      onPressed: _verifyAnswer,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle, size: 28),
                      label: const Text(
                        'تأكيد الإجابة',
                        style: TextStyle(
                          fontSize: 22,
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
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.4)),
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
            leading: const Icon(Icons.alarm_on, color: Colors.red),
            title: const Text('تحديات الصحيان'),
            subtitle: Text('${state.wakeChallenges.length} تحدي متاح'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WakeChallengeListScreen(),
              ),
            ),
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
                builder: (_) => const PomodoroSettingsScreen(),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
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
                  content: const Text(
                      'هيتم مسح كل المواعيد والتحديات والإحصائيات. متأكد؟'),
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
              if (ok == true && context.mounted) {
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
              Text('منبه المواعيد والمذاكرة وتحدي الصحيان',
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
              Text('الإصدار 1.3.0',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}