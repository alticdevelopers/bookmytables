import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_state.dart';
import '../core/theme.dart';

class MenuOffersPage extends StatefulWidget {
  const MenuOffersPage({super.key});

  @override
  State<MenuOffersPage> createState() => _MenuOffersPageState();
}

class _MenuOffersPageState extends State<MenuOffersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slug = AppState.instance.activeSlug;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text("Menu & Offers"),
        bottom: TabBar(
          controller: _tab, // ✅ use our TabController
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: "Menu"),
            Tab(text: "Today's Specials"),
            Tab(text: "Offers"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _menuTab(slug),
          _specialsTab(slug),
          _offersTab(slug),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.deepRed,
        onPressed: () {
          if (_tab.index == 0) _showAddMenuDialog(slug);
          if (_tab.index == 2) _showAddOfferDialog(slug);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- Safe getters to avoid Object? → String? issues ---
  String _s(Map<String, dynamic> m, String key) => (m[key] as String?) ?? "";
  double _d(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
  bool _b(Map<String, dynamic> m, String key, {bool fallback = true}) {
    final v = m[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == "true";
    return fallback;
  }

  // ================= MENU TAB =================
  Widget _menuTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("businesses")
          .doc(slug)
          .collection("menu")
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text("No menu items yet."));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: docs.map((d) {
            final data = d.data();
            final name = _s(data, "name");
            final price = _d(data, "price");
            final category = _s(data, "category");
            final available = _b(data, "available", fallback: true);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(name),
                subtitle: Text("\$${price.toStringAsFixed(2)} • $category"),
                trailing: Switch(
                  value: available,
                  activeColor: AppColors.deepRed,
                  onChanged: (v) {
                    FirebaseFirestore.instance
                        .collection("businesses")
                        .doc(slug)
                        .collection("menu")
                        .doc(d.id)
                        .update({"available": v});
                  },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ================= SPECIALS TAB =================
  Widget _specialsTab(String slug) {
    // Mark specials by setting "special": true on menu items
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("businesses")
          .doc(slug)
          .collection("menu")
          .where("special", isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text("No specials today. You can mark menu items as 'special'."),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: docs.map((d) {
            final data = d.data();
            final name = _s(data, "name");
            final price = _d(data, "price");
            final category = _s(data, "category");

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: AppColors.gold.withOpacity(0.1),
              child: ListTile(
                leading: const Icon(Icons.star, color: AppColors.gold),
                title: Text(name),
                subtitle: Text("\$${price.toStringAsFixed(2)} • $category"),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ================= OFFERS TAB =================
  Widget _offersTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("businesses")
          .doc(slug)
          .collection("offers")
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text("No active offers."));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: docs.map((d) {
            final data = d.data();
            final title = _s(data, "title");
            final description = _s(data, "description");
            final active = _b(data, "active", fallback: true);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(title),
                subtitle: Text(description),
                trailing: Switch(
                  value: active,
                  activeColor: AppColors.deepRed,
                  onChanged: (v) {
                    FirebaseFirestore.instance
                        .collection("businesses")
                        .doc(slug)
                        .collection("offers")
                        .doc(d.id)
                        .update({"active": v});
                  },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ================= ADD MENU ITEM =================
  Future<void> _showAddMenuDialog(String slug) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final category = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Menu Item"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: "Item name")),
            const SizedBox(height: 8),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price"),
            ),
            const SizedBox(height: 8),
            TextField(controller: category, decoration: const InputDecoration(labelText: "Category")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              final rawName = name.text.trim();
              if (rawName.isEmpty) return;

              final id = DateTime.now().millisecondsSinceEpoch.toString(); // ✅ String id
              final parsedPrice = double.tryParse(price.text.trim()) ?? 0.0;

              final item = {
                "id": id,
                "name": rawName,
                "price": parsedPrice,
                "available": true,
                "category": category.text.trim(),
                "createdAt": FieldValue.serverTimestamp(),
              };

              await FirebaseFirestore.instance
                  .collection("businesses")
                  .doc(slug)
                  .collection("menu")
                  .doc(id) // ✅ String
                  .set(item);

              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ================= ADD OFFER =================
  Future<void> _showAddOfferDialog(String slug) async {
    final title = TextEditingController();
    final description = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Offer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: "Title")),
            const SizedBox(height: 8),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: "Description"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              final rawTitle = title.text.trim();
              if (rawTitle.isEmpty) return;

              final id = DateTime.now().millisecondsSinceEpoch.toString(); // ✅ String id

              final offer = {
                "id": id,
                "title": rawTitle,
                "description": description.text.trim(),
                "active": true,
                "createdAt": FieldValue.serverTimestamp(),
              };

              await FirebaseFirestore.instance
                  .collection("businesses")
                  .doc(slug)
                  .collection("offers")
                  .doc(id) // ✅ String
                  .set(offer);

              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}