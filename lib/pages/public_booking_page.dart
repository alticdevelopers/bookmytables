import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Business profile loaded by slug for header
  Map<String, dynamic>? _biz;

  @override
  void initState() {
    super.initState();
    _loadBiz();
  }

  Future<void> _loadBiz() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection("businesses")
          .doc(widget.slug)
          .get();
      if (mounted) setState(() => _biz = snap.data());
    } catch (e) {
      debugPrint("Failed to load business header: $e");
    }
  }

  // ---- Safe getters (avoid Object? → String? errors) ----
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

  bool _b(Map<String, dynamic> m, String k, {bool fallback = false}) {
    final v = m[k];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == "true";
    return fallback;
  }

  bool get _isSubmitting => _loading;

  Future<void> _bookTable() async {
    // basic validation
    final nm = name.text.trim();
    final ph = phone.text.trim();
    if (nm.isEmpty || ph.isEmpty) {
      setState(() => _error = "Name and phone are required.");
      return;
    }

    // prevent past times when booking same day
    final now = DateTime.now();
    final when = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (!when.isAfter(now.subtract(const Duration(minutes: 1)))) {
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
      final data = {
        "id": id,
        "customerName": nm,
        "guests": int.tryParse(guests.text.trim()) ?? 2,
        "datetime": Timestamp.fromDate(when),
        "phone": ph,
        "notes": notes.text.trim(),
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection("businesses")
          .doc(widget.slug)
          .collection("requests")
          .doc(id)
          .set(data);

      if (!mounted) return;
      // clear form + success UI
      name.clear();
      phone.clear();
      notes.clear();
      guests.text = "2";
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request sent! The restaurant will confirm soon.")),
      );
      _showSuccessDialog();
    } on FirebaseException catch (e) {
      debugPrint("Firestore error: ${e.code} ${e.message}");
      if (mounted) {
        setState(() => _error = "Couldn’t send request. Please try again.");
      }
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

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(_s(_biz ?? {}, "businessName", fallback: "Book a Table")),
        backgroundColor: AppColors.deepRed,
      ),
      body: _loading
          ? const Center(child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 4)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _restaurantHeader(),
            const SizedBox(height: 20),
            Text("Booking Details", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _inputField(name, "Your Name", Icons.person),
            _inputField(phone, "Phone", Icons.phone, keyboard: TextInputType.phone),
            _inputField(guests, "Number of Guests", Icons.group, keyboard: TextInputType.number),
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
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate.isBefore(DateTime.now())
                              ? DateTime.now()
                              : selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 60)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    ),
                  ),
                ),
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
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _bookTable,
              icon: const Icon(Icons.check),
              label: const Text("Submit Booking"),
            ),
            const SizedBox(height: 20),
            Text("Available Tables", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _tablesStreamList(),
          ],
        ),
      ),
    );
  }

  // ========== Restaurant Header ==========
  Widget _restaurantHeader() {
    final m = _biz ?? const <String, dynamic>{};
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_s(m, "businessName", fallback: "Restaurant"),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "${_s(m, 'city')} ${_s(m, 'state')} ${_s(m, 'country')}".trim(),
              style: const TextStyle(color: Colors.black54),
            ),
            if (_s(m, "restaurantType").isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Cuisine: ${_s(m, 'restaurantType')}",
                    style: const TextStyle(color: Colors.black87)),
              ),
          ],
        ),
      ),
    );
  }

  // ========== Available Tables (live) ==========
  Widget _tablesStreamList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("businesses")
          .doc(widget.slug)
          .collection("tables")
          .where("available", isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Text("No tables currently available.");
        }
        return Column(
          children: docs.map((d) {
            final t = Map<String, dynamic>.from(d.data());
            final title = "${_s(t, 'name')} • ${_i(t, 'seats')} seats";
            final sub = _s(t, 'location', fallback: "—");
            final available = _b(t, 'available', fallback: true);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.table_bar, color: AppColors.deepRed),
                title: Text(title),
                subtitle: Text(sub),
                trailing: Icon(
                  available ? Icons.check_circle : Icons.block,
                  color: available ? Colors.green : Colors.redAccent,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ========== Utility Field Widget ==========
  Widget _inputField(TextEditingController c, String label, IconData icon, {TextInputType? keyboard}) {
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
}