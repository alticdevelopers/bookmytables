import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/theme.dart';

class PublicBookingPage extends StatefulWidget {
  final String slug;
  const PublicBookingPage({super.key, required this.slug});

  @override
  State<PublicBookingPage> createState() => _PublicBookingPageState();
}

class _PublicBookingPageState extends State<PublicBookingPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final notes = TextEditingController();
  final guests = TextEditingController(text: "2");

  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = const TimeOfDay(hour: 19, minute: 0);

  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _biz;

  // ── Timezone / holidays / vacations / business hours ──
  String _timezone = 'UTC';
  // Each holiday: { 'date': 'yyyy-MM-dd', 'reason': '...' }
  List<Map<String, String>> _holidays = [];
  Map<String, bool> _dayOpen = {};  // 'monday' → true/false
  Map<String, Map<String, dynamic>> _businessHours = {};  // full hours per day
  List<Map<String, String>> _serviceSlots = [];    // time ranges {start, end}

  // ── Table selection ──
  List<Map<String, dynamic>> _availableTables = [];
  String? _selectedTableId;
  String? _selectedTableName;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tableSub;

  // ── Today's Specials + Offers ──
  List<Map<String, dynamic>> _todaysSpecials = [];
  List<Map<String, dynamic>> _activeOffers   = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _specialsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offersSub;

  // UTC offset in minutes for the business timezone (no DST — best-effort)
  static const Map<String, int> _tzOffsetMinutes = {
    'America/New_York':   -300,
    'America/Chicago':    -360,
    'America/Denver':     -420,
    'America/Los_Angeles':-480,
    'America/Anchorage':  -540,
    'Pacific/Honolulu':   -600,
    'Europe/London':         0,
    'Europe/Paris':         60,
    'Europe/Berlin':        60,
    'Asia/Dubai':          240,
    'Asia/Kolkata':        330,  // +5:30
    'Asia/Singapore':      480,
    'Asia/Shanghai':       480,
    'Asia/Tokyo':          540,
    'Australia/Sydney':    600,
    'Pacific/Auckland':    720,
    'UTC':                   0,
  };

  static const List<String> _dayKeys = [
    'monday','tuesday','wednesday','thursday','friday','saturday','sunday'
  ];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bizSub;

  @override
  void initState() {
    super.initState();
    // Start listening immediately — don't wait for auth
    _bizSub = FirebaseFirestore.instance
        .collection("businesses")
        .doc(widget.slug)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      _parseBizData(snap.data()!);
    }, onError: (e) => debugPrint("Biz stream error: $e"));

    // Listen to available tables
    _tableSub = FirebaseFirestore.instance
        .collection("businesses")
        .doc(widget.slug)
        .collection("tables")
        .where("available", isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _availableTables = snap.docs.map((d) => Map<String, dynamic>.from(d.data())).toList();
        // Clear selection if selected table is no longer available
        if (_selectedTableId != null &&
            !_availableTables.any((t) => t['id'] == _selectedTableId)) {
          _selectedTableId = null;
          _selectedTableName = null;
        }
      });
    }, onError: (e) => debugPrint("Tables stream error: $e"));

    // Listen to today's specials
    _specialsSub = FirebaseFirestore.instance
        .collection("businesses")
        .doc(widget.slug)
        .collection("menu")
        .where("special", isEqualTo: true)
        .where("available", isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _todaysSpecials = snap.docs
            .map((d) => Map<String, dynamic>.from(d.data()))
            .toList();
      });
    }, onError: (e) => debugPrint("Specials stream error: $e"));

    // Listen to active offers
    _offersSub = FirebaseFirestore.instance
        .collection("businesses")
        .doc(widget.slug)
        .collection("offers")
        .where("active", isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activeOffers = snap.docs
            .map((d) => Map<String, dynamic>.from(d.data()))
            .toList();
      });
    }, onError: (e) => debugPrint("Offers stream error: $e"));

    // Auth in background — Firestore will re-emit once signed in
    _ensureAuth();
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint("Anon sign-in failed: $e");
    }
  }

  @override
  void dispose() {
    _bizSub?.cancel();
    _tableSub?.cancel();
    _specialsSub?.cancel();
    _offersSub?.cancel();
    super.dispose();
  }

  void _parseBizData(Map<String, dynamic> data) {
    // Parse timezone
    String newTimezone = 'UTC';
    final tz = data['timezone'];
    if (tz is String && _tzOffsetMinutes.containsKey(tz)) newTimezone = tz;

    // Parse holidays — supports old (string) and new ({date, reason}) formats
    List<Map<String, String>> newHolidays = [];
    if (data['holidays'] is List) {
      newHolidays = (data['holidays'] as List)
          .map<Map<String, String>>((h) {
            if (h is String) return {'date': h, 'reason': ''};
            return {
              'date':   (h['date']   ?? '').toString(),
              'reason': (h['reason'] ?? '').toString(),
            };
          })
          .toList();
    }

    // Parse business hours
    final Map<String, bool> newDayOpen = {};
    final Map<String, Map<String, dynamic>> newBusinessHours = {};
    if (data['businessHours'] is Map) {
      final hours = data['businessHours'] as Map<String, dynamic>;
      for (final day in _dayKeys) {
        final d = hours[day];
        newDayOpen[day] = (d is Map) ? (d['isOpen'] == true) : true;
        if (d is Map) {
          newBusinessHours[day] = {
            'isOpen': d['isOpen'] == true,
            'open':   (d['open']  ?? '').toString(),
            'close':  (d['close'] ?? '').toString(),
          };
        }
      }
    }

    // Parse service slots (time ranges)
    List<Map<String, String>> newServiceSlots = [];
    if (data['serviceSlots'] is List) {
      newServiceSlots = (data['serviceSlots'] as List)
          .map<Map<String, String>>((s) => {
                'start': (s['start'] ?? '').toString(),
                'end':   (s['end']   ?? '').toString(),
              })
          .toList()
        ..sort((a, b) => (a['start'] ?? '').compareTo(b['start'] ?? ''));
    }

    setState(() {
      _biz            = data;
      _timezone       = newTimezone;
      _holidays       = newHolidays;
      _dayOpen        = newDayOpen;
      _businessHours  = newBusinessHours;
      _serviceSlots   = newServiceSlots;
      // Snap selectedTime to first service slot start (if any)
      if (newServiceSlots.isNotEmpty) {
        final p = newServiceSlots.first['start']!.split(':');
        selectedTime =
            TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
    });
  }

  // ── Date selectable predicate ──
  bool _isDateSelectable(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    if (_holidays.any((h) => h['date'] == dateStr)) return false;
    if (_dayOpen.isNotEmpty) {
      final key = _dayKeys[day.weekday - 1];
      if (_dayOpen[key] == false) return false;
    }
    return true;
  }

  // ── Why is this date blocked? Returns reason string or "Closed" or null ──
  String? _whyBlocked(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final holiday = _holidays.where((h) => h['date'] == dateStr).firstOrNull;
    if (holiday != null) {
      final reason = holiday['reason'] ?? '';
      return reason.isNotEmpty ? reason : "Holiday";
    }
    if (_dayOpen.isNotEmpty) {
      final key = _dayKeys[day.weekday - 1];
      if (_dayOpen[key] == false) return "Closed";
    }
    return null;
  }

  // ── Convert picked local business-timezone datetime → UTC for Firestore ──
  DateTime _toUtc(DateTime localDate, TimeOfDay localTime) {
    final offsetMinutes = _tzOffsetMinutes[_timezone] ?? 0;
    final localDt = DateTime(
      localDate.year, localDate.month, localDate.day,
      localTime.hour, localTime.minute,
    );
    return localDt.subtract(Duration(minutes: offsetMinutes));
  }

  // ── Safe getters ──
  String _s(Map<String, dynamic> m, String k, {String fallback = ""}) {
    final v = m[k];
    if (v is String) return v;
    if (v == null) return fallback;
    return v.toString();
  }

  int _i(Map<String, dynamic> m, String k, {int fallback = 0}) {
    final v = m[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  Future<void> _bookTable() async {
    final nm = name.text.trim();
    final ph = phone.text.trim();
    if (nm.isEmpty || ph.isEmpty) {
      setState(() => _error = "Name and phone are required.");
      return;
    }

    if (_availableTables.isNotEmpty && _selectedTableId == null) {
      setState(() => _error = "Please select a table.");
      return;
    }

    if (!_isDateSelectable(selectedDate)) {
      setState(() => _error = "This date is unavailable. Please choose another.");
      return;
    }

    // Build UTC datetime using business timezone
    final utcWhen = _toUtc(selectedDate, selectedTime);
    if (!utcWhen.isAfter(DateTime.now().toUtc().subtract(const Duration(minutes: 1)))) {
      setState(() => _error = "Please choose a future time.");
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final id = "r${DateTime.now().microsecondsSinceEpoch}";
      await FirebaseFirestore.instance
          .collection("businesses")
          .doc(widget.slug)
          .collection("requests")
          .doc(id)
          .set({
        "id": id,
        "customerName": nm,
        "guests": int.tryParse(guests.text.trim()) ?? 2,
        "datetime": Timestamp.fromDate(utcWhen),
        "phone": ph,
        "notes": notes.text.trim(),
        "tableId": _selectedTableId,
        "tableName": _selectedTableName,
        "status": "pending",
        "timezone": _timezone,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      name.clear(); phone.clear(); notes.clear(); guests.text = "2";
      setState(() { _selectedTableId = null; _selectedTableName = null; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request sent! The restaurant will confirm soon.")),
      );
      _showSuccessDialog();
    } on FirebaseException catch (e) {
      debugPrint("Firestore error: ${e.code} ${e.message}");
      if (mounted) setState(() => _error = "Couldn't send request. Please try again.");
    } catch (e) {
      debugPrint("Booking error: $e");
      if (mounted) setState(() => _error = "Failed to book table.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Booking Sent"),
        content: const Text(
          "Your booking request has been sent to the restaurant. "
          "They will confirm shortly. Thank you!",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Map<String, String>? _holidayForDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _holidays.where((h) => h['date'] == dateStr).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, MMM d yyyy').format(selectedDate);
    final selectedHoliday = _holidayForDate(selectedDate);
    final isSelectedDateHoliday = selectedHoliday != null;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(_s(_biz ?? {}, "businessName", fallback: "Book a Table")),
        backgroundColor: AppColors.deepRed,
      ),
      body: (_biz == null || _loading)
          ? const Center(
              child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(strokeWidth: 4)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _restaurantHeader(),
                  const SizedBox(height: 16),

                  // ── Selected date is a holiday: hide menu/offers/specials ──
                  if (isSelectedDateHoliday) ...[
                    _buildHolidayClosedNotice(selectedHoliday!),
                    const SizedBox(height: 20),
                    Text("Choose Another Date",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                  ] else ...[
                    _buildTodayHolidayBanner(),
                    _buildAvailabilityNotice(),
                    _buildPublicInfoSections(widget.slug),
                    const SizedBox(height: 24),
                    Text("Make a Reservation",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                  ],

                  // ── Step 1: Select Date & Time ──
                  _stepLabel("Select Time Slot", icon: Icons.access_time),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Date"),
                          subtitle: Text(formattedDate),
                          trailing: IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              DateTime initial = selectedDate;
                              if (!_isDateSelectable(initial)) {
                                initial = DateTime.now();
                              }
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initial.isBefore(DateTime.now())
                                    ? DateTime.now()
                                    : initial,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 60)),
                                selectableDayPredicate: _isDateSelectable,
                              );
                              if (picked != null) {
                                setState(() => selectedDate = picked);
                              }
                            },
                          ),
                        ),
                      ),
                      if (_serviceSlots.isEmpty)
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Time"),
                            subtitle: Text(selectedTime.format(context)),
                            trailing: IconButton(
                              icon: const Icon(Icons.access_time),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: selectedTime,
                                );
                                if (picked != null) {
                                  setState(() => selectedTime = picked);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),

                  // ── Service slot chips ──
                  if (_serviceSlots.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _serviceSlots.map((slot) {
                        final sp = slot['start']!.split(':');
                        final ep = slot['end']!.split(':');
                        final slotStart = TimeOfDay(
                            hour: int.parse(sp[0]),
                            minute: int.parse(sp[1]));
                        final isSelected =
                            selectedTime.hour == slotStart.hour &&
                                selectedTime.minute == slotStart.minute;
                        final startLabel = slotStart.format(context);
                        final endLabel = TimeOfDay(
                                hour: int.parse(ep[0]),
                                minute: int.parse(ep[1]))
                            .format(context);
                        return GestureDetector(
                          onTap: () =>
                              setState(() => selectedTime = slotStart),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.deepRed
                                  : AppColors.deepRed.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.deepRed.withValues(
                                    alpha: isSelected ? 1 : 0.3),
                              ),
                            ),
                            child: Text(
                              "$startLabel – $endLabel",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.deepRed,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Blocked date notice ──
                  if (_whyBlocked(selectedDate) != null)
                    Builder(builder: (context) {
                      final reason = _whyBlocked(selectedDate)!;
                      final isClosed = reason == "Closed";
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              isClosed ? Icons.block : Icons.event_busy,
                              size: 14,
                              color: Colors.red.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isClosed
                                    ? "We are Closed on this day — please choose another"
                                    : "$reason — please choose another date",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  // ── Timezone notice ──
                  if (_timezone != 'UTC')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule,
                              size: 14, color: Colors.black45),
                          const SizedBox(width: 4),
                          Text(
                            "Times are in ${_timezone.replaceAll('_', ' ')}",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),

                  // ── Step 2: Select Table ──
                  if (_availableTables.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _stepLabel("Available Table", icon: Icons.table_bar),
                    const SizedBox(height: 10),
                    _buildTableSelector(),
                  ],

                  // ── Step 3: Guest Details ──
                  const SizedBox(height: 20),
                  _stepLabel("Your Details", icon: Icons.person),
                  const SizedBox(height: 10),
                  _inputField(name, "Your Name", Icons.person),
                  _inputField(phone, "Phone", Icons.phone,
                      keyboard: TextInputType.phone),
                  _inputField(guests, "Number of Guests", Icons.group,
                      keyboard: TextInputType.number),

                  // ── Step 4: Special Requests ──
                  const SizedBox(height: 8),
                  _stepLabel("Special Requests", icon: Icons.edit_note),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Special Requests / Notes",
                      alignLabelWithHint: true,
                    ),
                  ),

                  // ── Step 5: Submit ──
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 14)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _bookTable,
                      icon: const Icon(Icons.check),
                      label: const Text("Submit Booking"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _restaurantHeader() {
    final m = _biz ?? const <String, dynamic>{};
    final logoUrl = _s(m, 'logoUrl');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFFFFF0EE),
              backgroundImage:
                  logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
              child: logoUrl.isEmpty
                  ? const Icon(Icons.store, size: 36, color: AppColors.deepRed)
                  : null,
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_s(m, "businessName", fallback: "Restaurant"),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    [_s(m, 'city'), _s(m, 'state'), _s(m, 'country')]
                        .where((e) => e.isNotEmpty)
                        .join(", "),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (_s(m, "restaurantType").isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text("Cuisine: ${_s(m, 'restaurantType')}",
                          style: const TextStyle(color: Colors.black87)),
                    ),
                  if (_s(m, "about").isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_s(m, "about"),
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step label ──
  Widget _stepLabel(String title, {required IconData icon}) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.deepRed, size: 22),
            const SizedBox(width: 16),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ── Selectable table list ──
  Widget _buildTableSelector() {
    return Column(
      children: _availableTables.map((table) {
        final id       = (table['id'] ?? '').toString();
        final tName    = (table['name'] ?? '').toString();
        final seats    = _i(table, 'seats');
        final location = _s(table, 'location');
        final isSelected = _selectedTableId == id;

        return GestureDetector(
          onTap: () => setState(() {
            _selectedTableId   = id;
            _selectedTableName = tName;
          }),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.deepRed.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.deepRed
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.table_bar,
                    color: isSelected ? AppColors.deepRed : Colors.grey.shade500,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tName,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isSelected
                                  ? AppColors.deepRed
                                  : Colors.black87)),
                      if (location.isNotEmpty)
                        Text(location,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.deepRed.withValues(alpha: 0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$seats seat${seats != 1 ? 's' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.deepRed
                            : Colors.grey.shade700),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle,
                      color: AppColors.deepRed, size: 20),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════ PUBLIC INFO SECTIONS ═══════════════
  Widget _buildPublicInfoSections(String slug) {
    final menuStream = FirebaseFirestore.instance
        .collection('businesses').doc(slug).collection('menu')
        .where('available', isEqualTo: true)
        .snapshots();

    return Column(
      children: [
        // ── Service Hours ──
        _buildServiceHoursSection(),

        // ── Holidays ──
        _buildHolidaysSection(),

        // ── Menu ──
        _infoExpansionTile(
          icon: Icons.restaurant_menu,
          title: 'Menu',
          stream: menuStream,
          builder: (docs) {
            if (docs.isEmpty) return _publicEmptyText('No items available');
            return Column(
              children: docs.map((d) {
                final data  = d.data();
                final name  = _s(data, 'name');
                final price = _s(data, 'price') != ''
                    ? (data['price'] as num?)?.toStringAsFixed(2) ?? '0.00'
                    : '0.00';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.circle,
                      size: 8, color: AppColors.deepRed),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Text('₹$price',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepRed)),
                );
              }).toList(),
            );
          },
        ),

        // ── Today's Specials + Offers ──
        _buildTodaysSpecialsSection(),

      ],
    );
  }

  String _formatTime(String t) {
    try {
      final parts = t.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final period = h < 12 ? 'AM' : 'PM';
      final hour12 = h % 12 == 0 ? 12 : h % 12;
      return '$hour12:${m.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return t;
    }
  }

  Widget _buildServiceHoursSection() {
    if (_businessHours.isEmpty && _serviceSlots.isEmpty) {
      return const SizedBox.shrink();
    }

    final todayKey = _dayKeys[DateTime.now().weekday - 1];

    // Per-day open/close rows
    final dayRows = _businessHours.isEmpty
        ? <Widget>[]
        : _dayKeys.map((day) {
            final info = _businessHours[day];
            if (info == null) return const SizedBox.shrink();
            final isOpen  = info['isOpen'] == true;
            final open    = (info['open']  as String? ?? '');
            final close   = (info['close'] as String? ?? '');
            final label   = day[0].toUpperCase() + day.substring(1);
            final isToday = day == todayKey;
            return ListTile(
              dense: true,
              leading: Icon(
                isOpen ? Icons.schedule : Icons.block,
                size: 18,
                color: isOpen ? AppColors.deepRed : Colors.grey,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? AppColors.deepRed : null,
                ),
              ),
              trailing: Text(
                isOpen
                    ? (open.isNotEmpty && close.isNotEmpty
                        ? '${_formatTime(open)} – ${_formatTime(close)}'
                        : 'Open')
                    : 'Closed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isOpen ? Colors.black87 : Colors.grey,
                ),
              ),
            );
          }).toList();

    // Service slot rows (booking time windows)
    final sorted = [..._serviceSlots]
      ..sort((a, b) => (a['start'] ?? '').compareTo(b['start'] ?? ''));
    final slotRows = sorted.map((slot) {
      final start = slot['start'] ?? '';
      final end   = slot['end']   ?? '';
      return ListTile(
        dense: true,
        leading: const Icon(Icons.access_time_filled,
            size: 18, color: AppColors.deepRed),
        title: Text(
          '${_formatTime(start)}  –  ${_formatTime(end)}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      );
    }).toList();

    return _SmoothExpandCard(
      key: const ValueKey('hours_card'),
      initiallyExpanded: true,
      leading: const Icon(Icons.access_time, color: AppColors.deepRed, size: 22),
      title: const Text(
        'Service Hours',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      badge: const SizedBox.shrink(),
      children: [
        const Divider(height: 1),
        if (slotRows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'Booking Windows',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Column(children: slotRows),
        ],
        if (dayRows.isNotEmpty) ...[
          if (slotRows.isNotEmpty)
            const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'Weekly Schedule',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Column(children: dayRows),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTodaysSpecialsSection() {
    final totalCount = _todaysSpecials.length + _activeOffers.length;

    return _SmoothExpandCard(
      key: const ValueKey('specials_offers_card'),
      showArrow: false,
      initiallyExpanded: true,
      leading: const Icon(Icons.star, color: AppColors.gold, size: 22),
      title: const Text("Today's Specials",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$totalCount',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.gold,
                fontWeight: FontWeight.bold)),
      ),
      children: [
        const Divider(height: 1),
        if (_todaysSpecials.isEmpty && _activeOffers.isEmpty)
          _publicEmptyText('No specials or offers today')
        else
          Column(
            children: [
              ..._todaysSpecials.map((data) {
                final name  = _s(data, 'name');
                final price = (data['price'] as num?)?.toStringAsFixed(2) ?? '0.00';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.star,
                      size: 18, color: AppColors.gold),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Text('₹$price',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepRed)),
                );
              }),
              ..._activeOffers.map((data) {
                final title = _s(data, 'title');
                final desc  = _s(data, 'description');
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_offer,
                      size: 18, color: AppColors.deepRed),
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: desc.isNotEmpty ? Text(desc) : null,
                );
              }),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHolidaysSection() {
    final sorted = [..._holidays]
      ..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));

    if (sorted.isEmpty) return const SizedBox.shrink();

    return _SmoothExpandCard(
      key: const ValueKey('holidays_card'),
      initiallyExpanded: sorted.isNotEmpty,
      leading: const Icon(Icons.event_busy, color: Colors.orange, size: 22),
      title: const Text(
        'Holidays',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${sorted.length}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      children: [
        const Divider(height: 1),
        if (sorted.isEmpty)
          _publicEmptyText('No holidays listed')
        else
          Column(
            children: sorted.map((h) {
              final dateStr = h['date'] ?? '';
              final reason  = (h['reason'] ?? '').trim();
              String dateLabel = dateStr;
              try {
                dateLabel = DateFormat('EEE, MMM d yyyy')
                    .format(DateTime.parse(dateStr));
              } catch (_) {}
              final todayStr =
                  DateFormat('yyyy-MM-dd').format(DateTime.now());
              final isToday = dateStr == todayStr;
              return ListTile(
                dense: true,
                leading: Icon(
                  isToday ? Icons.celebration : Icons.event_busy,
                  size: 18,
                  color: Colors.orange,
                ),
                title: Text(
                  dateLabel,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: reason.isNotEmpty
                    ? Text(reason)
                    : isToday
                        ? const Text('Today is a holiday')
                        : null,
                trailing: isToday
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _infoExpansionTile({
    required IconData icon,
    required String title,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) builder,
    Color iconColor = AppColors.deepRed,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return _SmoothExpandCard(
          key: ValueKey('info_tile_$title'),
          showArrow: false,
          leading: Icon(icon, color: iconColor, size: 22),
          title: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          badge: snap.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.deepRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${docs.length}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.deepRed,
                          fontWeight: FontWeight.bold)),
                ),
          children: [
            const Divider(height: 1),
            builder(docs),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _publicEmptyText(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(msg,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      );

  Widget _inputField(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.deepRed),
        ),
      ),
    );
  }

  // ── Full-page holiday closed notice ──
  Widget _buildHolidayClosedNotice(Map<String, String> holiday) {
    final reason = (holiday['reason'] ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.celebration, color: Colors.orange, size: 48),
          const SizedBox(height: 12),
          const Text(
            "Holiday",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.orange,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            "We are closed on this date. Please choose another date to make a booking.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.orange.shade700),
          ),
        ],
      ),
    );
  }

  // ── Holiday banners ──
  Widget _buildTodayHolidayBanner() {
    if (_holidays.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final banners = <Widget>[];

    // Today's holiday
    final todayHoliday =
        _holidays.where((h) => h['date'] == todayStr).firstOrNull;
    if (todayHoliday != null) {
      banners.add(_holidayBanner(
        icon: Icons.celebration,
        title: "Today is a holiday",
        reason: (todayHoliday['reason'] ?? '').trim(),
        isToday: true,
      ));
    }

    // Upcoming holidays (next 60 days, excluding today)
    final upcoming = _holidays.where((h) {
      if (h['date'] == todayStr) return false;
      try {
        final dt = DateTime.parse(h['date']!);
        return dt.isAfter(now) &&
            dt.isBefore(now.add(const Duration(days: 60)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));

    for (final h in upcoming) {
      String dateLabel = h['date'] ?? '';
      try {
        dateLabel =
            DateFormat('EEE, MMM d').format(DateTime.parse(h['date']!));
      } catch (_) {}
      banners.add(_holidayBanner(
        icon: Icons.event_busy,
        title: "Holiday on $dateLabel",
        reason: (h['reason'] ?? '').trim(),
        isToday: false,
      ));
    }

    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(children: banners);
  }

  Widget _holidayBanner({
    required IconData icon,
    required String title,
    required String reason,
    required bool isToday,
  }) {
    final color = isToday ? Colors.orange : Colors.deepOrange;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: color.shade800,
                  ),
                ),
                if (reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 13,
                        color: color.shade700,
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

  // ── Availability notice card ──
  Widget _buildAvailabilityNotice() {
    final closedDays = <String>[];
    for (int i = 0; i < _dayKeys.length; i++) {
      if (_dayOpen[_dayKeys[i]] == false) {
        // Capitalise first letter
        final label = _dayKeys[i][0].toUpperCase() + _dayKeys[i].substring(1);
        closedDays.add(label);
      }
    }

    // Upcoming holidays within the next 60 days
    final now = DateTime.now();
    final upcomingHolidays = _holidays.where((h) {
      try {
        final dt = DateTime.parse(h['date']!);
        return !dt.isBefore(DateTime(now.year, now.month, now.day)) &&
            dt.isBefore(now.add(const Duration(days: 60)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));

    if (closedDays.isEmpty && upcomingHolidays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.orange),
              SizedBox(width: 6),
              Text(
                "Availability Notice",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          if (closedDays.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: closedDays.map((day) => _noticeBadge(
                label: "Closed",
                value: day,
                color: Colors.red.shade600,
                bg: Colors.red.shade50,
              )).toList(),
            ),
          ],
          if (upcomingHolidays.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: upcomingHolidays.map((h) {
                final dateLabel = DateFormat('MMM d')
                    .format(DateTime.parse(h['date']!));
                final reason = (h['reason'] ?? '').isNotEmpty
                    ? h['reason']!
                    : 'Holiday';
                return _noticeBadge(
                  label: reason,
                  value: dateLabel,
                  color: Colors.deepOrange.shade700,
                  bg: Colors.orange.shade50,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noticeBadge({
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: "$label  ",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Smooth expanding card with AnimatedSize + rotating arrow ──
class _SmoothExpandCard extends StatefulWidget {
  final Widget leading;
  final Widget title;
  final Widget badge;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool showArrow;

  const _SmoothExpandCard({
    super.key,
    required this.leading,
    required this.title,
    required this.badge,
    required this.children,
    this.initiallyExpanded = false,
    this.showArrow = true,
  });

  @override
  State<_SmoothExpandCard> createState() => _SmoothExpandCardState();
}

class _SmoothExpandCardState extends State<_SmoothExpandCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(_SmoothExpandCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  widget.leading,
                  const SizedBox(width: 16),
                  Expanded(child: widget.title),
                  widget.badge,
                  if (widget.showArrow) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.expand_more),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
