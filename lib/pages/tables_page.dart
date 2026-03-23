import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_state.dart';
import '../core/theme.dart';

class TablesPage extends StatefulWidget {
  const TablesPage({super.key});

  @override
  State<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends State<TablesPage> {
  // --- quick helpers for type safety ---
  String _s(Map<String, dynamic> m, String key, {String fallback = ""}) {
    final v = m[key];
    if (v is String) return v;
    if (v == null) return fallback;
    return v.toString();
  }

  int _i(Map<String, dynamic> m, String key, {int fallback = 0}) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool _b(Map<String, dynamic> m, String key, {bool fallback = true}) {
    final v = m[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == "true";
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final slug = AppState.instance.activeSlug;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text("Manage Tables")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("businesses")
            .doc(slug)
            .collection("tables")
            .orderBy("name")
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No tables added yet.",
                style: TextStyle(color: AppColors.textDark, fontSize: 16),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = Map<String, dynamic>.from(docs[i].data());
              final name = _s(data, "name");
              final seats = _i(data, "seats");
              final location = _s(data, "location", fallback: "—");
              final available = _b(data, "available");

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.deepRed.withOpacity(0.1),
                    child: const Icon(Icons.table_bar, color: AppColors.deepRed),
                  ),
                  title: Text("$name • $seats seats"),
                  subtitle: Text(location),
                  trailing: Switch(
                    value: available,
                    activeColor: AppColors.deepRed,
                    onChanged: (v) {
                      FirebaseFirestore.instance
                          .collection("businesses")
                          .doc(slug)
                          .collection("tables")
                          .doc(docs[i].id)
                          .update({"available": v});
                    },
                  ),
                  onTap: () => _editTableDialog(slug, docs[i].id, data),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.deepRed,
        onPressed: () => _addTableDialog(slug),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ==================== Add Table ====================
  Future<void> _addTableDialog(String slug) async {
    final name = TextEditingController();
    final seats = TextEditingController();
    String location = "Indoor";
    bool available = true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Table"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: "Table Name"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: seats,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Number of Seats"),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: location,
              items: const [
                DropdownMenuItem(value: "Indoor", child: Text("Indoor")),
                DropdownMenuItem(value: "Outdoor", child: Text("Outdoor")),
              ],
              onChanged: (v) => location = v ?? "Indoor",
              decoration: const InputDecoration(labelText: "Location"),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("Available"),
                const Spacer(),
                Switch(
                  value: available,
                  onChanged: (v) => available = v,
                  activeColor: AppColors.deepRed,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || seats.text.trim().isEmpty) return;
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              final table = {
                "id": id,
                "name": name.text.trim(),
                "seats": int.tryParse(seats.text.trim()) ?? 2,
                "location": location,
                "available": available,
                "createdAt": FieldValue.serverTimestamp(),
              };
              await FirebaseFirestore.instance
                  .collection("businesses")
                  .doc(slug)
                  .collection("tables")
                  .doc(id)
                  .set(table);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ==================== Edit Table ====================
  Future<void> _editTableDialog(String slug, String docId, Map<String, dynamic> raw) async {
    final data = Map<String, dynamic>.from(raw);
    final name = TextEditingController(text: _s(data, "name"));
    final seats = TextEditingController(text: _i(data, "seats").toString());
    String location = _s(data, "location", fallback: "Indoor");
    bool available = _b(data, "available");

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Table"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: "Table Name")),
            const SizedBox(height: 8),
            TextField(
              controller: seats,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Number of Seats"),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: location,
              items: const [
                DropdownMenuItem(value: "Indoor", child: Text("Indoor")),
                DropdownMenuItem(value: "Outdoor", child: Text("Outdoor")),
              ],
              onChanged: (v) => location = v ?? "Indoor",
              decoration: const InputDecoration(labelText: "Location"),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("Available"),
                const Spacer(),
                Switch(
                  value: available,
                  onChanged: (v) => available = v,
                  activeColor: AppColors.deepRed,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection("businesses")
                  .doc(slug)
                  .collection("tables")
                  .doc(docId)
                  .delete();
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection("businesses")
                  .doc(slug)
                  .collection("tables")
                  .doc(docId)
                  .update({
                "name": name.text.trim(),
                "seats": int.tryParse(seats.text.trim()) ?? 2,
                "location": location,
                "available": available,
              });
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