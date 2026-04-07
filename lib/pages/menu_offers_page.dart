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
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Safe getters ──
  String _s(Map<String, dynamic> m, String k) => (m[k] as String?) ?? '';
  double _d(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
  bool _b(Map<String, dynamic> m, String k, {bool fallback = true}) {
    final v = m[k];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  CollectionReference<Map<String, dynamic>> _menuCol(String slug) =>
      FirebaseFirestore.instance.collection('businesses').doc(slug).collection('menu');

  CollectionReference<Map<String, dynamic>> _offersCol(String slug) =>
      FirebaseFirestore.instance.collection('businesses').doc(slug).collection('offers');

  @override
  Widget build(BuildContext context) {
    final slug = AppState.instance.activeSlug;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('Menu & Offers'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant_menu, size: 18), text: 'Menu'),
            Tab(icon: Icon(Icons.category, size: 18), text: 'Available Types'),
            Tab(icon: Icon(Icons.star, size: 18), text: "Today's Specials"),
            Tab(icon: Icon(Icons.local_offer, size: 18), text: 'Offers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _menuTab(slug),
          _typesTab(slug),
          _specialsTab(slug),
          _offersTab(slug),
        ],
      ),
      floatingActionButton: _buildFab(slug),
    );
  }

  // ── FAB — context-aware per tab ──
  Widget? _buildFab(String slug) {
    final idx = _tab.index;
    if (idx == 2) return null; // Specials — mark from Menu tab
    if (idx == 1) return null; // Types — auto-generated from menu

    return FloatingActionButton.extended(
      backgroundColor: AppColors.deepRed,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(idx == 3 ? 'Add Offer' : 'Add Item'),
      onPressed: () {
        if (idx == 0) _showAddMenuDialog(slug);
        if (idx == 3) _showAddOfferDialog(slug);
      },
    );
  }

  // ═══════════════════════ MENU TAB ═══════════════════════
  Widget _menuTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _menuCol(slug).orderBy('createdAt').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.restaurant_menu,
            title: 'No menu items yet',
            subtitle: 'Tap + to add your first item',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final id       = docs[i].id;
            final name     = _s(data, 'name');
            final price    = _d(data, 'price');
            final category = _s(data, 'category');
            final available = _b(data, 'available');
            final isSpecial = _b(data, 'special', fallback: false);

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Special star
                    GestureDetector(
                      onTap: () => _menuCol(slug)
                          .doc(id)
                          .update({'special': !isSpecial}),
                      child: Icon(
                        isSpecial ? Icons.star : Icons.star_border,
                        color: isSpecial
                            ? AppColors.gold
                            : Colors.grey.shade400,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            '₹${price.toStringAsFixed(2)}'
                            '${category.isNotEmpty ? '  •  $category' : ''}',
                            style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // Available toggle
                    Switch(
                      value: available,
                      activeColor: AppColors.deepRed,
                      onChanged: (v) =>
                          _menuCol(slug).doc(id).update({'available': v}),
                    ),
                    // Delete
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => _confirmDelete(
                        context: context,
                        label: name,
                        onConfirm: () =>
                            _menuCol(slug).doc(id).delete(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════ AVAILABLE TYPES TAB ═══════════════════════
  Widget _typesTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _menuCol(slug).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.category,
            title: 'No categories yet',
            subtitle: 'Add menu items with categories to see them here',
          );
        }

        // Group by category
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final d in docs) {
          final data     = d.data();
          final category = _s(data, 'category').trim();
          final key      = category.isEmpty ? 'Uncategorised' : category;
          grouped.putIfAbsent(key, () => []);
          grouped[key]!.add({...data, '_id': d.id});
        }
        final keys = grouped.keys.toList()..sort();

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: keys.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final cat   = keys[i];
            final items = grouped[cat]!;
            final availableCount =
                items.where((e) => _b(e, 'available')).length;

            return _SmoothCategoryCard(
              key: ValueKey('cat_$cat'),
              category: cat,
              totalCount: items.length,
              availableCount: availableCount,
              children: items.map((item) {
                final name      = _s(item, 'name');
                final price     = _d(item, 'price');
                final available = _b(item, 'available');
                final isSpecial = _b(item, 'special', fallback: false);
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isSpecial ? Icons.star : Icons.circle,
                    color: isSpecial
                        ? AppColors.gold
                        : (available
                            ? Colors.green
                            : Colors.grey.shade400),
                    size: 16,
                  ),
                  title: Text(name),
                  subtitle: Text('₹${price.toStringAsFixed(2)}'),
                  trailing: Text(
                    available ? 'Available' : 'Unavailable',
                    style: TextStyle(
                      fontSize: 12,
                      color: available ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════ TODAY'S SPECIALS TAB ═══════════════════════
  Widget _specialsTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _menuCol(slug).where('special', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.star_border,
            title: "No specials today",
            subtitle:
                "Go to Menu tab and tap ☆ on any item to mark it as today's special",
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data     = docs[i].data();
            final id       = docs[i].id;
            final name     = _s(data, 'name');
            final price    = _d(data, 'price');
            final category = _s(data, 'category');

            return Card(
              elevation: 2,
              color: AppColors.gold.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.gold,
                  child: Icon(Icons.star, color: Colors.white, size: 20),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '₹${price.toStringAsFixed(2)}'
                  '${category.isNotEmpty ? '  •  $category' : ''}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                trailing: TextButton.icon(
                  onPressed: () =>
                      _menuCol(slug).doc(id).update({'special': false}),
                  icon: const Icon(Icons.star,
                      color: AppColors.gold, size: 18),
                  label: const Text('Unmark',
                      style: TextStyle(color: AppColors.gold)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════ OFFERS TAB ═══════════════════════
  Widget _offersTab(String slug) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _offersCol(slug).orderBy('createdAt').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.local_offer,
            title: 'No offers yet',
            subtitle: 'Tap + to create your first offer',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data        = docs[i].data();
            final id          = docs[i].id;
            final title       = _s(data, 'title');
            final description = _s(data, 'description');
            final active      = _b(data, 'active');

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: active
                          ? AppColors.deepRed.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      child: Icon(Icons.local_offer,
                          color: active
                              ? AppColors.deepRed
                              : Colors.grey.shade400,
                          size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(description,
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13)),
                          ],
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              active ? 'Active' : 'Inactive',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: active
                                      ? Colors.green.shade700
                                      : Colors.grey,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Switch(
                          value: active,
                          activeColor: AppColors.deepRed,
                          onChanged: (v) =>
                              _offersCol(slug).doc(id).update({'active': v}),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => _confirmDelete(
                            context: context,
                            label: title,
                            onConfirm: () =>
                                _offersCol(slug).doc(id).delete(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════ ADD MENU ITEM ═══════════════════════
  Future<void> _showAddMenuDialog(String slug) async {
    final nameCtrl     = TextEditingController();
    final priceCtrl    = TextEditingController();
    final categoryCtrl = TextEditingController();
    bool isSpecial = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Menu Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Item Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Price', prefixText: '₹ '),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: categoryCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Today's Special"),
                  secondary: Icon(
                    isSpecial ? Icons.star : Icons.star_border,
                    color: isSpecial ? AppColors.gold : Colors.grey,
                  ),
                  value: isSpecial,
                  activeColor: AppColors.deepRed,
                  onChanged: (v) => setLocal(() => isSpecial = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final rawName = nameCtrl.text.trim();
                if (rawName.isEmpty) return;
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                await _menuCol(slug).doc(id).set({
                  'id': id,
                  'name': rawName,
                  'price': double.tryParse(priceCtrl.text.trim()) ?? 0.0,
                  'category': categoryCtrl.text.trim(),
                  'available': true,
                  'special': isSpecial,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (!mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════ ADD OFFER ═══════════════════════
  Future<void> _showAddOfferDialog(String slug) async {
    final titleCtrl = TextEditingController();
    final descCtrl  = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final rawTitle = titleCtrl.text.trim();
              if (rawTitle.isEmpty) return;
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              await _offersCol(slug).doc(id).set({
                'id': id,
                'title': rawTitle,
                'description': descCtrl.text.trim(),
                'active': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ HELPERS ═══════════════════════
  Future<void> _confirmDelete({
    required BuildContext context,
    required String label,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _SmoothCategoryCard extends StatefulWidget {
  final String category;
  final int totalCount;
  final int availableCount;
  final List<Widget> children;

  const _SmoothCategoryCard({
    super.key,
    required this.category,
    required this.totalCount,
    required this.availableCount,
    required this.children,
  });

  @override
  State<_SmoothCategoryCard> createState() => _SmoothCategoryCardState();
}

class _SmoothCategoryCardState extends State<_SmoothCategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.deepRed.withValues(alpha: 0.1),
                    child: Text(
                      '${widget.totalCount}',
                      style: const TextStyle(
                          color: AppColors.deepRed,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.category,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                          '${widget.availableCount} of ${widget.totalCount} available',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.expand_more),
                  ),
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
                      children: [
                        const Divider(height: 1),
                        ...widget.children,
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
