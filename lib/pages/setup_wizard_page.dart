import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_state.dart';
import '../core/notifications.dart';
import '../core/theme.dart';
import 'dashboard_page.dart';

class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key});

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController();
  final _restaurantType = TextEditingController();
  final _about = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _businessName.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    _restaurantType.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final app = AppState.instance;
      final p = app.profile;

      p.businessName = _businessName.text.trim();
      p.email = _email.text.trim();
      p.phone = _phone.text.trim();
      p.city = _city.text.trim();
      p.state = _state.text.trim();
      p.country = _country.text.trim();
      p.restaurantType = _restaurantType.text.trim();
      p.about = _about.text.trim();

      final desired = p.businessName ?? "";
      final slug = await app.ensureUniqueSlug(
        desired: desired,
        city: p.city,
        restaurantType: p.restaurantType,
      );
      app.profileSlugOverride = slug;

      final ownerEmail = FirebaseAuth.instance.currentUser?.email;
      await app.saveProfileToFirestore(slug, ownerEmail: ownerEmail);

      // Also link user → slug
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .set({"slug": slug}, SetOptions(merge: true));
      }

      // Save FCM token now that setup is complete
      await saveFcmToken();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text("Set Up Your Restaurant"),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              "Business Details",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.deepRed,
              ),
            ),
            const SizedBox(height: 16),
            _field(_businessName, "Restaurant Name", Icons.store),
            _field(_email, "Email", Icons.email),
            _field(_phone, "Phone", Icons.phone),
            const Divider(height: 32),
            _field(_city, "City", Icons.location_city),
            _field(_state, "State", Icons.map),
            _field(_country, "Country", Icons.public),
            _field(_restaurantType, "Cuisine Type (e.g., Italian, Chinese)", Icons.restaurant_menu),
            const SizedBox(height: 16),
            TextFormField(
              controller: _about,
              decoration: const InputDecoration(
                labelText: "About / Description",
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
              ),
            const SizedBox(height: 8),
            if (_saving)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton.icon(
                onPressed: _onSave,
                icon: const Icon(Icons.check),
                label: const Text("Save & Continue"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.deepRed),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
      ),
    );
  }
}