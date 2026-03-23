import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import 'menu_offers_page.dart';
import 'tables_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _reqPageController = PageController(viewportFraction: 0.92);
  int _reqPage = 0;
  int _reqCount = 0; // for dots

  @override
  void dispose() {
    _reqPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final slug = app.activeSlug;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text("Book My Tables"),
        actions: [
          IconButton(
            tooltip: "Menu & Offers",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MenuOffersPage()),
            ),
            icon: const Icon(Icons.restaurant_menu),
          ),
          IconButton(
            tooltip: "Tables",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TablesPage()),
            ),
            icon: const Icon(Icons.table_bar),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _businessHeader(),
          const SizedBox(height: 12),
          _summaryRow(),
          const SizedBox(height: 16),
          _requestsSection(slug),
          const SizedBox(height: 16),
          _upcomingSection(slug),
          const SizedBox(height: 96), // space for FABs
        ],
      ),

      // Floating cluster: Add (top) + Share (bottom)
      floatingActionButton: _fabCluster(context),
    );
  }

  // ===== Header with business name & location =====
  Widget _businessHeader() {
    final p = AppState.instance.profile;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.deepRed,
              child: Icon(Icons.store, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.businessName ?? "Your Restaurant",
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((p.city ?? '').isNotEmpty) p.city,
                      if ((p.state ?? '').isNotEmpty) p.state,
                      if ((p.country ?? '').isNotEmpty) p.country
                    ].where((e) => (e ?? "").isNotEmpty).join(", "),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Summary three-cards row =====
  Widget _summaryRow() {
    final app = AppState.instance;
    final slug = app.activeSlug;

    return StreamBuilder(
      stream: app.watchReservations(slug),
      builder: (context, resSnap) {
        final reservations = resSnap.data ?? const <Reservation>[];
        final todayCount = reservations
            .where((r) => _isSameDay(r.datetime, DateTime.now()))
            .length;

        return StreamBuilder(
          stream: app.watchRequests(slug),
          builder: (context, reqSnap) {
            final requests = reqSnap.data ?? const <ReservationRequest>[];

            return Row(
              children: [
                Expanded(
                  child: _statCard(
                    title: "Today’s Bookings",
                    value: "$todayCount",
                    icon: Icons.event_available,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    title: "Pending Requests",
                    value: "${requests.length}",
                    icon: Icons.inbox,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    title: "Total Tables",
                    value: "—", // populate from tables page if you track count
                    icon: Icons.table_bar,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        // let it grow as needed; no hard height
        constraints: const BoxConstraints(minHeight: 108),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFFFF0EE),
              Color(0xFFFFF0EE),
              Color(0xFFFFF6F4),
            ],
            stops: [0.0, 0.72, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ✅ shrink to fit (prevents overflow)
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title at top
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A1C17),
                height: 1.15, // a touch tighter
              ),
            ),
            const SizedBox(height: 8),
            // Icon + Number row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFEFD7D2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8), // was 10
                  child: Icon(icon, color: const Color(0xFF7B1E12), size: 20),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    (value.isEmpty) ? "—" : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26, // was 28
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3A1C17),
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== Requests (carousel with swipe) =====
  Widget _requestsSection(String slug) {
    final app = AppState.instance;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(Icons.inbox),
              const SizedBox(width: 8),
              Text("Requests", style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: "Prev",
                onPressed: () {
                  final t = (_reqPage - 1).clamp(0, (_reqCount - 1).clamp(0, 9999));
                  _reqPageController.animateToPage(
                    t,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  );
                },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: "Next",
                onPressed: () {
                  final t = (_reqPage + 1).clamp(0, (_reqCount - 1).clamp(0, 9999));
                  _reqPageController.animateToPage(
                    t,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  );
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 230,
            child: StreamBuilder<List<ReservationRequest>>(
              stream: app.watchRequests(slug),
              builder: (context, snap) {
                final list = snap.data ?? const <ReservationRequest>[];
                _reqCount = list.length;
                if (list.isEmpty) {
                  return const Center(child: Text("No new requests"));
                }
                return PageView.builder(
                  controller: _reqPageController,
                  onPageChanged: (i) => setState(() => _reqPage = i),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _RequestCard(
                    request: list[i],
                    onAccept: () => app.acceptRequest(slug, list[i]),
                    onDecline: () => app.declineRequest(slug, list[i]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _dotsIndicator(_reqCount),
        ]),
      ),
    );
  }

  Widget _dotsIndicator(int count) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _reqPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.deepRed : Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }

  // ===== Upcoming reservations (list) =====
  Widget _upcomingSection(String slug) {
    final app = AppState.instance;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(Icons.event),
              const SizedBox(width: 8),
              Text("Upcoming Reservations",
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<List<Reservation>>(
            stream: app.watchReservations(slug),
            builder: (context, snap) {
              final list = (snap.data ?? const <Reservation>[])
                ..sort((a, b) => a.datetime.compareTo(b.datetime));
              final futureOnly = list.where((r) => r.datetime.isAfter(DateTime.now())).toList();

              if (futureOnly.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text("No upcoming reservations")),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: futureOnly.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final r = futureOnly[i];
                  return ListTile(
                    leading: const Icon(Icons.schedule, color: AppColors.deepRed),
                    title: Text("${r.customerName} • ${r.guests} guests"),
                    subtitle: Text(_fmtDT(r.datetime)),
                    trailing: (r.phone != null && r.phone!.trim().isNotEmpty)
                        ? IconButton(
                      tooltip: "Call",
                      onPressed: () => _call(r.phone!),
                      icon: const Icon(Icons.call),
                    )
                        : null,
                  );
                },
              );
            },
          ),
        ]),
      ),
    );
  }

  // ===== Floating cluster =====
  Widget _fabCluster(BuildContext context) {
    final app = AppState.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: "fab-add",
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add),
          label: const Text("Add"),
          backgroundColor: AppColors.deepRed,
          foregroundColor: Colors.white,
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: "fab-share",
          onPressed: () async {
            final link = app.publicUrl;
            await Clipboard.setData(ClipboardData(text: link));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Public link copied: $link"),
                action: SnackBarAction(
                  label: "Open",
                  onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                ),
              ),
            );
          },
          icon: const Icon(Icons.link),
          label: const Text("Share Link"),
          backgroundColor: AppColors.deepRed,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }

  // ===== Manual add dialog (quick reservation) =====
  Future<void> _showAddDialog() async {
    final name = TextEditingController();
    final guests = TextEditingController(text: "2");
    DateTime when = DateTime.now().add(const Duration(hours: 2));
    final phone = TextEditingController();
    final notes = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Create Reservation"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: "Customer name")),
            const SizedBox(height: 8),
            TextField(
              controller: guests,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Guests"),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_fmtDT(when)),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 180)),
                    initialDate: when,
                  );
                  if (d == null) return;
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(when),
                  );
                  if (t == null) return;
                  when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  setState(() {});
                },
              ),
            ),
            TextField(controller: phone, decoration: const InputDecoration(labelText: "Phone (optional)")),
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: const InputDecoration(labelText: "Notes (optional)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final slug = AppState.instance.activeSlug;
              final r = Reservation(
                id: "res_${DateTime.now().microsecondsSinceEpoch}",
                customerName: name.text.trim(),
                guests: int.tryParse(guests.text.trim()) ?? 2,
                datetime: when,
                phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
              );
              await AppState.instance.addReservation(slug, r); // ✅ public helper
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _call(String number) async {
    final normalized = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: normalized);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtDT(DateTime dt) {
    final d = DateFormat('yyyy-MM-dd').format(dt);
    final t = DateFormat('h:mm a').format(dt);
    return "$d • $t";
  }
}

// ===== Single request card (like BMA spec you approved) =====
class _RequestCard extends StatelessWidget {
  final ReservationRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(request.datetime);
    final timeStr = DateFormat('h:mm a').format(request.datetime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${request.customerName} · Table for ${request.guests}",
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text("$dateStr • $timeStr"),
            if ((request.phone ?? "").isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text("Phone: ${request.phone}"),
              ),
            if ((request.notes ?? "").isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Notes: ${request.notes}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: "Call",
                  onPressed: (request.phone ?? "").isEmpty
                      ? null
                      : () {
                    final normalized =
                    request.phone!.replaceAll(RegExp(r'[^0-9+]'), '');
                    final uri = Uri(scheme: 'tel', path: normalized);
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.call, size: 20),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onDecline,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text("Decline"),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text("Accept"),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}