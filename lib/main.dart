// ═══════════════════════════════════════════════════════════════
//  mawaid - تطبيق مواعيد ومنبه المذاكرة
//  المهندس يوسف أحمد مصطفى
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  Global Navigator Key
// ═══════════════════════════════════════════════════════════════
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

// ═══════════════════════════════════════════════════════════════
//  Main - تهيئة خدمة المنبه
// ═══════════════════════════════════════════════════════════════
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
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

  Appointment({
    required this.id,
    required this.title,
    required this.note,
    required this.dateTime,
    this.soundPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'dateTime': dateTime.toIso8601String(),
        'soundPath': soundPath,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] ?? '') as String,
        dateTime: DateTime.parse(j['dateTime'] as String),
        soundPath: j['soundPath'] as String?,
      );
}

class StudySession {
  final DateTime date;
  final int minutes;
  StudySession({required this.date, required this.minutes});

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'minutes': minutes};

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        date: DateTime.parse(j['date'] as String),
        minutes: j['minutes'] as int,
      );
}

// ═══════════════════════════════════════════════════════════════
//  Alarm Service - إدارة المنبهات باستخدام مكتبة alarm
// ═══════════════════════════════════════════════════════════════
class AlarmService {
  AlarmService._();
  static final AlarmService I = AlarmService._();

  // معرفات المنبهات النشطة (int لأن المكتبة بتطلب int)
  final Map<String, int> _alarmIds = {};

  int _generateId(String appointmentId) {
    // نحوّل الـ String ID لـ int ثابت باستخدام hashCode
    return appointmentId.hashCode & 0x7fffffff;
  }

  /// جدولة منبه جديد
  Future<void> schedule(Appointment a) async {
    final alarmId = _generateId(a.id);
    _alarmIds[a.id] = alarmId;

    // لو الملف الصوتي موجود، استخدمه. لو مش موجود، استخدم الصوت الافتراضي
    String? soundPath;
    if (a.soundPath != null && File(a.soundPath!).existsSync()) {
      soundPath = a.soundPath;
    }

    final settings = AlarmSettings(
      id: alarmId,
      dateTime: a.dateTime,
      assetAudioPath: soundPath, // مسار الملف الصوتي المخصص
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true, // عشان تظهر الشاشة كاملة
      volumeSettings: VolumeSettings.fade(
        volume: 1.0,
        fadeDuration: const Duration(seconds: 3),
        volumeEnforced: false,
      ),
      notificationSettings: NotificationSettings(
        title: '⏰ ${a.title}',
        body: a.note.isEmpty ? 'اضغط لإيقاف المنبه' : a.note,
        stopButton: 'إيقاف',
        icon: 'notification_icon',
        iconColor: const Color(0xff862778),
      ),
    );

    await Alarm.set(alarmSettings: settings);
  }

  /// إلغاء منبه
  Future<void> cancel(String appointmentId) async {
    final alarmId = _alarmIds[appointmentId];
    if (alarmId != null) {
      await Alarm.stop(alarmId);
      _alarmIds.remove(appointmentId);
    }
  }

  /// إلغاء كل المنبهات
  Future<void> cancelAll() async {
    await Alarm.stopAll();
    _alarmIds.clear();
  }
}

// ═══════════════════════════════════════════════════════════════
//  App State
// ═══════════════════════════════════════════════════════════════
class AppState extends ChangeNotifier {
  static const _kAppts = 'appointments_v3';
  static const _kSessions = 'sessions_v3';
  static const _kDark = 'dark_mode_v3';

  final List<Appointment> appointments = [];
  final List<StudySession> sessions = [];
  bool isDark = false;

  StreamSubscription? _alarmSub;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    isDark = sp.getBool(_kDark) ?? false;

    // تحميل المواعيد
    final aRaw = sp.getString(_kAppts);
    if (aRaw != null) {
      try {
        final List list = jsonDecode(aRaw) as List;
        appointments.clear();
        appointments.addAll(
          list.map((e) => Appointment.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {}
    }

    // تحميل الجلسات
    final sRaw = sp.getString(_kSessions);
    if (sRaw != null) {
      try {
        final List list = jsonDecode(sRaw) as List;
        sessions.clear();
        sessions.addAll(
          list.map((e) => StudySession.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {}
    }

    // الاستماع لأحداث المنبه
    _alarmSub = Alarm.ringStream.stream.listen((alarmSettings) {
      _onAlarmRing(alarmSettings);
    });

    // إعادة جدولة المواعيد القادمة
    for (final a in appointments) {
      if (a.dateTime.isAfter(DateTime.now())) {
        await AlarmService.I.schedule(a);
      }
    }

    notifyListeners();
  }

  void _onAlarmRing(AlarmSettings settings) {
    // البحث عن الموعد المرتبط بالمنبه
    final appt = appointments.firstWhere(
      (a) => a.id.hashCode & 0x7fffffff == settings.id,
      orElse: () => Appointment(
        id: settings.id.toString(),
        title: 'موعد',
        note: '',
        dateTime: DateTime.now(),
      ),
    );

    // فتح شاشة المنبه
    navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AlarmScreen(appointment: appt),
      ),
    );
  }

  // ─── الحفظ ───
  Future<void> _persistAppts() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kAppts,
      jsonEncode(appointments.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistSessions() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kSessions,
      jsonEncode(sessions.map((e) => e.toJson()).toList()),
    );
  }

  // ─── إضافة موعد ───
  Future<void> addAppointment(Appointment a) async {
    appointments.add(a);
    appointments.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    await _persistAppts();
    await AlarmService.I.schedule(a);
    notifyListeners();
  }

  // ─── تعديل موعد ───
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

  // ─── حذف موعد ───
  Future<void> deleteAppointment(String id) async {
    appointments.removeWhere((x) => x.id == id);
    await AlarmService.I.cancel(id);
    await _persistAppts();
    notifyListeners();
  }

  // ─── مسح كل البيانات ───
  Future<void> clearAll() async {
    appointments.clear();
    sessions.clear();
    await AlarmService.I.cancelAll();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAppts);
    await sp.remove(_kSessions);
    notifyListeners();
  }

  // ─── الوضع الليلي ───
  Future<void> toggleDark() async {
    isDark = !isDark;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDark, isDark);
    notifyListeners();
  }

  // ─── إضافة جلسة مذاكرة ───
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
      locale: const Locale('ar'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواعيدي'),
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
        ],
      ),
      body: appts.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_off, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('مفيش مواعيد لسه',
                      style: TextStyle(fontSize: 20, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('اضغط + عشان تضيف موعد',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: appts.length,
              itemBuilder: (_, i) {
                final a = appts[i];
                final soon = a.dateTime.difference(DateTime.now()).inMinutes;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: soon < 0
                          ? Colors.grey
                          : soon < 60
                              ? Colors.red
                              : Colors.teal,
                      child: const Icon(Icons.alarm, color: Colors.white),
                    ),
                    title: Text(a.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('EEEE d MMM - hh:mm a', 'ar')
                            .format(a.dateTime)),
                        if (a.note.isNotEmpty)
                          Text(a.note,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddAppointmentScreen(existing: a),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('حذف الموعد'),
                                content: Text('متأكد إنك عايز تحذف "${a.title}"؟'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('إلغاء')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('حذف',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await context
                                  .read<AppState>()
                                  .deleteAppointment(a.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم حذف الموعد ✅')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AddAppointmentScreen())),
        icon: const Icon(Icons.add_alarm),
        label: const Text('إضافة موعد'),
      ),
    );
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

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl.text = widget.existing!.title;
      _noteCtrl.text = widget.existing!.note;
      _date = widget.existing!.dateTime;
      _time = TimeOfDay.fromDateTime(widget.existing!.dateTime);
      _soundPath = widget.existing!.soundPath;
    } else {
      final d = DateTime.now().add(const Duration(minutes: 5));
      _date = d;
      _time = TimeOfDay.fromDateTime(d);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickSound() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (r == null || r.files.single.path == null) return;
      final src = File(r.files.single.path!);
      // انسخه لمكان دائم عشان المكتبة تقدر توصل له
      final dir = await getApplicationDocumentsDirectory();
      final ext = r.files.single.extension ?? 'mp3';
      final dest = File(
          '${dir.path}/alarm_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await src.copy(dest.path);
      setState(() => _soundPath = dest.path);
      if (mounted) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم الموعد')),
      );
      return;
    }
    final dt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    if (dt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الوقت ده فات! اختار وقت في المستقبل')),
      );
      return;
    }

    final state = context.read<AppState>();
    if (widget.existing == null) {
      final a = Appointment(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        note: _noteCtrl.text.trim(),
        dateTime: dt,
        soundPath: _soundPath,
      );
      await state.addAppointment(a);
    } else {
      final a = widget.existing!;
      a.title = title;
      a.note = _noteCtrl.text.trim();
      a.dateTime = dt;
      a.soundPath = _soundPath;
      await state.updateAppointment(a);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.existing == null
                ? 'تم حفظ الموعد ✅'
                : 'تم تعديل الموعد ✅')),
      );
      Navigator.pop(context);
    }
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(DateFormat('yyyy/MM/dd').format(_date)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(_time.format(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note),
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ الموعد'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Alarm Screen (شاشة المنبه)
// ═══════════════════════════════════════════════════════════════
class AlarmScreen extends StatelessWidget {
  final Appointment appointment;
  const AlarmScreen({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm, size: 140, color: Colors.white),
                const SizedBox(height: 32),
                const Text('⏰ وقت الموعد',
                    style: TextStyle(color: Colors.white70, fontSize: 18)),
                const SizedBox(height: 12),
                Text(
                  appointment.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (appointment.note.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    appointment.note,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  DateFormat('hh:mm a').format(appointment.dateTime),
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 70,
                  child: FilledButton.icon(
                    onPressed: () async {
                      // إيقاف الصوت عن طريق مكتبة alarm
                      await Alarm.stop(appointment.id.hashCode & 0x7fffffff);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                    ),
                    icon: const Icon(Icons.stop_circle, size: 32),
                    label: const Text('إيقاف',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
  static const studyMin = 25;
  static const breakMin = 5;

  int _remaining = studyMin * 60;
  bool _isStudy = true;
  bool _running = false;
  Timer? _t;

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
    setState(() {
      _running = false;
      _isStudy = true;
      _remaining = studyMin * 60;
    });
  }

  Future<void> _switch() async {
    _t?.cancel();
    if (_isStudy) {
      await context.read<AppState>().addSession(studyMin);
    }
    setState(() {
      _isStudy = !_isStudy;
      _remaining = (_isStudy ? studyMin : breakMin) * 60;
      _running = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isStudy ? 'ابدأ المذاكرة!' : 'وقت الراحة!')),
      );
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    final color = _isStudy ? Colors.teal : Colors.orange;
    return Scaffold(
      appBar: AppBar(title: const Text('بومودورو')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isStudy ? '📚 وقت المذاكرة' : '☕ وقت الراحة',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 24),
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$m:$s',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _pause : _start,
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  label: Text(_running ? 'إيقاف مؤقت' : 'ابدأ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size(140, 52),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة'),
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
                  leading: const Icon(Icons.check_circle, color: Colors.teal),
                  title: Text('${x.minutes} دقيقة'),
                  subtitle:
                      Text(DateFormat('yyyy/MM/dd - hh:mm a').format(x.date)),
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
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
              Text('الإصدار 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}