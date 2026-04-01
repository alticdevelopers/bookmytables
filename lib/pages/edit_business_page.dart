import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import 'login_page.dart';

class EditBusinessPage extends StatefulWidget {
  const EditBusinessPage({super.key});

  @override
  State<EditBusinessPage> createState() => _EditBusinessPageState();
}

class _EditBusinessPageState extends State<EditBusinessPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _countryCtrl;
  late TextEditingController _typeCtrl;
  late TextEditingController _aboutCtrl;

  // Logo
  File? _imageFile;
  String _existingLogoUrl = '';

  static const List<String> _timezones = [
    'America/New_York', 'America/Chicago', 'America/Denver',
    'America/Los_Angeles', 'America/Anchorage', 'Pacific/Honolulu',
    'Europe/London', 'Europe/Paris', 'Europe/Berlin',
    'Asia/Dubai', 'Asia/Kolkata', 'Asia/Singapore',
    'Asia/Shanghai', 'Asia/Tokyo', 'Australia/Sydney',
    'Pacific/Auckland', 'UTC',
  ];
  String _selectedTimezone = 'UTC';

  static const List<String> _dayNames = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ];
  static const List<String> _dayLabels = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  late Map<String, Map<String, dynamic>> _businessHours;
  // Each holiday: { 'date': 'yyyy-MM-dd', 'reason': '...' }
  List<Map<String, String>> _holidays = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = AppState.instance.profile;
    _nameCtrl  = TextEditingController(text: p.businessName ?? '');
    _phoneCtrl = TextEditingController(text: p.phone ?? '');
    _emailCtrl = TextEditingController(text: p.email ?? '');
    _cityCtrl  = TextEditingController(text: p.city ?? '');
    _stateCtrl = TextEditingController(text: p.state ?? '');
    _countryCtrl = TextEditingController(text: p.country ?? '');
    _typeCtrl  = TextEditingController(text: p.restaurantType ?? '');
    _aboutCtrl = TextEditingController(text: p.about ?? '');

    _businessHours = {};
    for (final day in _dayNames) {
      _businessHours[day] = {
        'isOpen': day != 'sunday',
        'open': '09:00',
        'close': '21:00',
      };
    }

    _loadExtraData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _cityCtrl.dispose(); _stateCtrl.dispose(); _countryCtrl.dispose();
    _typeCtrl.dispose(); _aboutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExtraData() async {
    try {
      final slug = AppState.instance.activeSlug;
      final doc = await FirebaseFirestore.instance
          .collection('businesses').doc(slug).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;

      final tz = data['timezone'] ?? 'UTC';
      if (_timezones.contains(tz)) _selectedTimezone = tz;

      _existingLogoUrl = data['logoUrl'] ?? '';

      if (data['businessHours'] != null) {
        final hours = data['businessHours'] as Map<String, dynamic>;
        for (final day in _dayNames) {
          if (hours[day] != null) {
            final d = hours[day] as Map<String, dynamic>;
            _businessHours[day] = {
              'isOpen': d['isOpen'] ?? true,
              'open':   d['open']   ?? '09:00',
              'close':  d['close']  ?? '21:00',
            };
          }
        }
      }

      if (data['holidays'] != null) {
        final raw = data['holidays'] as List;
        _holidays = raw.map<Map<String, String>>((h) {
          if (h is String) return {'date': h, 'reason': ''};
          return {
            'date':   (h['date']   ?? '').toString(),
            'reason': (h['reason'] ?? '').toString(),
          };
        }).toList();
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  // ── Logo picker ──
  Future<void> _pickLogo() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not pick image: $e")),
        );
      }
    }
  }

  // ── Upload logo to Firebase Storage ──
  Future<String> _uploadLogo(File file, String slug) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('business_logos/$slug.jpg');
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final app  = AppState.instance;
      final slug = app.activeSlug;

      // Upload logo if a new one was picked
      String logoUrl = _existingLogoUrl;
      if (_imageFile != null) {
        logoUrl = await _uploadLogo(_imageFile!, slug);
      }

      // Update profile in memory
      app.profile.businessName  = _nameCtrl.text.trim();
      app.profile.phone         = _phoneCtrl.text.trim();
      app.profile.email         = _emailCtrl.text.trim();
      app.profile.city          = _cityCtrl.text.trim();
      app.profile.state         = _stateCtrl.text.trim();
      app.profile.country       = _countryCtrl.text.trim();
      app.profile.restaurantType = _typeCtrl.text.trim();
      app.profile.about         = _aboutCtrl.text.trim();

      final hoursMap = <String, dynamic>{};
      for (final day in _dayNames) {
        hoursMap[day] = {
          'isOpen': _businessHours[day]!['isOpen'],
          'open':   _businessHours[day]!['open'],
          'close':  _businessHours[day]!['close'],
        };
      }

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(slug)
          .set({
        ...app.profile.toMap(slug: slug),
        'logoUrl':       logoUrl,
        'timezone':      _selectedTimezone,
        'businessHours': hoursMap,
        'holidays': _holidays
            .map((h) => {'date': h['date'], 'reason': h['reason']})
            .toList(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Business updated successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Account"),
        content: const Text(
            "This will permanently delete your account and all business data. This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final slug = AppState.instance.activeSlug;
        await FirebaseFirestore.instance.collection('businesses').doc(slug).delete();
        await user.delete();
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          e.code == 'requires-recent-login'
              ? "Please sign out and sign in again before deleting."
              : "Delete failed: ${e.message}",
        )),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickTime(String day, String field) async {
    final parts  = (_businessHours[day]![field] as String).split(':');
    final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked  = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _businessHours[day]![field] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  String _formatTime(String t) {
    final p  = t.split(':');
    final h  = int.parse(p[0]);
    final m  = p[1];
    final pd = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $pd';
  }

  Future<void> _addHoliday() async {
    final dateCtrl   = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? dateError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Add Holiday"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date field ──
              TextField(
                controller: dateCtrl,
                keyboardType: TextInputType.datetime,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Date",
                  hintText: "DD / MM / YYYY",
                  prefixIcon: const Icon(Icons.calendar_today,
                      color: AppColors.deepRed),
                  errorText: dateError,
                  suffixIcon: IconButton(
                    tooltip: "Pick from calendar",
                    icon: const Icon(Icons.date_range, color: AppColors.deepRed),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        dateCtrl.text = DateFormat('dd / MM / yyyy').format(picked);
                        setLocal(() => dateError = null);
                      }
                    },
                  ),
                ),
                onChanged: (_) => setLocal(() => dateError = null),
              ),
              const SizedBox(height: 4),
              const Text(
                "Type as DD / MM / YYYY  or tap 📅 to pick",
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const SizedBox(height: 12),
              // ── Reason field ──
              TextField(
                controller: reasonCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: "Reason",
                  hintText: "e.g. Christmas, National Day",
                  prefixIcon: Icon(Icons.label_outline, color: AppColors.deepRed),
                ),
                maxLength: 50,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                final raw = dateCtrl.text.replaceAll(RegExp(r'[\s/]'), '');
                DateTime? parsed;

                if (raw.length == 8) {
                  final day   = int.tryParse(raw.substring(0, 2));
                  final month = int.tryParse(raw.substring(2, 4));
                  final year  = int.tryParse(raw.substring(4, 8));
                  if (day != null && month != null && year != null) {
                    try {
                      parsed = DateTime(year, month, day);
                      if (parsed.day != day ||
                          parsed.month != month ||
                          parsed.year != year) parsed = null;
                    } catch (_) {}
                  }
                }

                if (parsed == null) {
                  setLocal(() => dateError = "Enter a valid date (DD / MM / YYYY)");
                  return;
                }
                if (parsed.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
                  setLocal(() => dateError = "Date must be today or in the future");
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final raw = dateCtrl.text.replaceAll(RegExp(r'[\s/]'), '');
    if (raw.length == 8) {
      final day   = int.tryParse(raw.substring(0, 2));
      final month = int.tryParse(raw.substring(2, 4));
      final year  = int.tryParse(raw.substring(4, 8));
      if (day != null && month != null && year != null) {
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime(year, month, day));
        if (_holidays.every((h) => h['date'] != dateStr)) {
          setState(() => _holidays.add({
            'date':   dateStr,
            'reason': reasonCtrl.text.trim(),
          }));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text("Edit Business"),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _save,
              child: const Text("Save",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Logo ──
                  _buildLogoCard(),
                  const SizedBox(height: 14),

                  // ── Business Info ──
                  _sectionCard(
                    title: "Business Info",
                    icon: Icons.store,
                    children: [
                      _field(_nameCtrl, "Business Name", Icons.store, required: true),
                      _field(_phoneCtrl, "Phone", Icons.phone, type: TextInputType.phone),
                      _field(_emailCtrl, "Email", Icons.email, type: TextInputType.emailAddress),
                      _field(_cityCtrl, "City", Icons.location_city),
                      _field(_stateCtrl, "State / Province", Icons.map),
                      _field(_countryCtrl, "Country", Icons.public),
                      _field(_typeCtrl, "Restaurant Type", Icons.restaurant_menu,
                          hint: "e.g. Italian, Cafe, Fast Food"),
                      _field(_aboutCtrl, "About", Icons.info_outline,
                          maxLines: 3, maxLength: 200),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Timezone ──
                  _sectionCard(
                    title: "Timezone",
                    icon: Icons.schedule,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedTimezone,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.public, color: AppColors.deepRed),
                          labelText: "Timezone",
                        ),
                        items: _timezones
                            .map((tz) => DropdownMenuItem(
                                  value: tz,
                                  child: Text(tz.replaceAll('_', ' '),
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedTimezone = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Business Hours ──
                  _buildHoursCard(),
                  const SizedBox(height: 14),

                  // ── Holidays ──
                  _buildHolidaysCard(),
                  const SizedBox(height: 24),

                  // ── Save ──
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text("Save Changes", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Delete Account ──
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _deleteAccount,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text("Delete Account",
                          style: TextStyle(color: Colors.red, fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Logo card ──
  Widget _buildLogoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.image, color: AppColors.deepRed, size: 20),
              SizedBox(width: 8),
              Text("Restaurant Logo",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 20),
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: const Color(0xFFFFF0EE),
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!) as ImageProvider
                          : (_existingLogoUrl.isNotEmpty
                              ? NetworkImage(_existingLogoUrl)
                              : null),
                      child: (_imageFile == null && _existingLogoUrl.isEmpty)
                          ? const Icon(Icons.store, size: 48, color: AppColors.deepRed)
                          : null,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.deepRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text("Tap to change logo",
                  style: TextStyle(color: Colors.black45, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card wrapper ──
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: AppColors.deepRed, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 20),
            ...children
                .expand((w) => [w, const SizedBox(height: 12)])
                .toList()
              ..removeLast(),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    String? hint,
    bool required = false,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.deepRed),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? "Required" : null
          : null,
    );
  }

  // ── Business Hours ──
  Widget _buildHoursCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.access_time, color: AppColors.deepRed, size: 20),
              SizedBox(width: 8),
              Text("Business Hours",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const Divider(height: 20),
            ...List.generate(_dayNames.length, (i) {
              final day   = _dayNames[i];
              final label = _dayLabels[i];
              final isOpen = _businessHours[day]!['isOpen'] as bool;
              final open   = _businessHours[day]!['open'] as String;
              final close  = _businessHours[day]!['close'] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 82,
                      child: Text(label,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    Switch(
                      value: isOpen,
                      activeColor: AppColors.deepRed,
                      onChanged: (v) =>
                          setState(() => _businessHours[day]!['isOpen'] = v),
                    ),
                    if (isOpen) ...[
                      _timeChip(open,  onTap: () => _pickTime(day, 'open')),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text("–", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      _timeChip(close, onTap: () => _pickTime(day, 'close')),
                    ] else
                      Text("Closed",
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _timeChip(String time, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0EE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.deepRed.withValues(alpha: 0.3)),
        ),
        child: Text(_formatTime(time),
            style: const TextStyle(fontSize: 13, color: AppColors.deepRed)),
      ),
    );
  }

  // ── Holidays ──
  Widget _buildHolidaysCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [
                  Icon(Icons.event_busy, color: AppColors.deepRed, size: 20),
                  SizedBox(width: 8),
                  Text("Holidays",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                IconButton(
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.add_circle, color: AppColors.deepRed, size: 26),
                  tooltip: "Add holiday",
                ),
              ],
            ),
            const Divider(height: 8),
            if (_holidays.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text("No holidays added",
                    style: TextStyle(color: Colors.grey.shade500)),
              )
            else
              ...(_holidays
                ..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? '')))
                  .asMap()
                  .entries
                  .map((entry) {
                    final i = entry.key;
                    final h = entry.value;
                    final d = DateTime.parse(h['date']!);
                    final reason = h['reason'] ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.calendar_today,
                          size: 18, color: AppColors.deepRed),
                      title: Text(DateFormat('MMM dd, yyyy').format(d)),
                      subtitle: reason.isNotEmpty
                          ? Text(reason,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12))
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 20),
                        onPressed: () =>
                            setState(() => _holidays.removeAt(i)),
                      ),
                    );
                  }),
          ],
        ),
      ),
    );
  }
}
