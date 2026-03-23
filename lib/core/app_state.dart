import 'package:cloud_firestore/cloud_firestore.dart';

/// Central Firestore + business logic handler for Book My Tables
/// Used throughout the app via `AppState.instance`

class AppState {
  AppState._();
  static final instance = AppState._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -------- Profile --------
  final UserProfile profile = UserProfile();
  String? profileSlugOverride;

  String get activeSlug => profileSlugOverride ?? profile.slug;
  String get publicUrl => "https://go.bookmytables.com/$activeSlug";

  // ===== Collections =====
  CollectionReference<Map<String, dynamic>> get _biz =>
      _db.collection("businesses");
  DocumentReference<Map<String, dynamic>> _bizDoc(String slug) =>
      _biz.doc(slug);
  CollectionReference<Map<String, dynamic>> _reqCol(String slug) =>
      _bizDoc(slug).collection("requests");
  CollectionReference<Map<String, dynamic>> _resCol(String slug) =>
      _bizDoc(slug).collection("reservations");
  CollectionReference<Map<String, dynamic>> _menuCol(String slug) =>
      _bizDoc(slug).collection("menu");
  CollectionReference<Map<String, dynamic>> _offersCol(String slug) =>
      _bizDoc(slug).collection("offers");

  // ===== Slug helpers =====
  String _slugify(String input) {
    final s = input.trim().toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r"-+"), "-")
        .replaceAll(RegExp(r"^-|-$"), "");
    return s.isEmpty ? "restaurant" : s;
  }

  /// Builds a SEO-friendly slug: business-name-city-restaurantType (unique)
  Future<String> ensureUniqueSlug({
    required String desired,
    String? city,
    String? restaurantType,
  }) async {
    Future<bool> exists(String s) async => (await _biz.doc(s).get()).exists;

    String base = _slugify(desired);
    if ((city ?? "").trim().isNotEmpty) base = _slugify("$base-${city!.trim()}");
    if ((restaurantType ?? "").trim().isNotEmpty) {
      base = _slugify("$base-${restaurantType!.trim()}");
    }

    if (!await exists(base)) return base;

    for (int i = 2; i < 9999; i++) {
      final candidate = _slugify("$base-$i");
      if (!await exists(candidate)) return candidate;
    }
    return _slugify("$base-${DateTime.now().millisecondsSinceEpoch}");
  }

  // ===== Firestore profile ops =====
  Future<void> saveProfileToFirestore(String slug, {String? ownerEmail}) async {
    final data = profile.toMap(slug: slug);
    if (ownerEmail != null) data["ownerEmail"] = ownerEmail;
    await _biz.doc(slug).set(data, SetOptions(merge: true));
  }

  Future<UserProfile?> loadProfileBySlug(String slug) async {
    final snap = await _biz.doc(slug).get();
    if (!snap.exists) return null;
    return UserProfile.fromMap(snap.data()!);
  }

  // ===== Requests / Reservations =====
  Stream<List<ReservationRequest>> watchRequests(String slug) {
    return _reqCol(slug)
        .orderBy("datetime")
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final m = d.data();
      return ReservationRequest.fromMap(m);
    }).toList());
  }

  Stream<List<Reservation>> watchReservations(String slug) {
    return _resCol(slug)
        .orderBy("datetime")
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final m = d.data();
      return Reservation.fromMap(m);
    }).toList());
  }

  Future<void> acceptRequest(String slug, ReservationRequest r) async {
    final batch = _db.batch();
    final reqRef = _reqCol(slug).doc(r.id);
    final resRef = _resCol(slug).doc("res_${r.id}");
    batch.set(resRef, r.toReservationMap());
    batch.delete(reqRef);
    await batch.commit();
  }

  Future<void> declineRequest(String slug, ReservationRequest r) async {
    await _reqCol(slug).doc(r.id).delete();
  }

  // === NEW: Reservation helpers so UI never touches _resCol directly ===
  Future<void> addReservation(String slug, Reservation r) async {
    await _resCol(slug).doc(r.id).set(r.toMap());
  }

  Future<void> updateReservation(String slug, Reservation r) async {
    await _resCol(slug).doc(r.id).update(r.toMap());
  }

  Future<void> deleteReservation(String slug, String reservationId) async {
    await _resCol(slug).doc(reservationId).delete();
  }

  // ===== Menu & Offers =====
  Future<void> addMenuItem(String slug, MenuItem item) async {
    await _menuCol(slug).doc(item.id).set(item.toMap());
  }

  Future<void> addOffer(String slug, OfferItem offer) async {
    await _offersCol(slug).doc(offer.id).set(offer.toMap());
  }
}

// =====================================================
// ==================== DATA MODELS ====================
// =====================================================

class UserProfile {
  String? businessName;
  String? email;
  String? phone;
  String? city;
  String? state;
  String? country;
  String? restaurantType;
  String? about;

  bool get isSetupComplete =>
      (businessName ?? "").isNotEmpty &&
          (email ?? "").isNotEmpty &&
          (city ?? "").isNotEmpty &&
          (country ?? "").isNotEmpty;

  String get slug {
    final s = (businessName ?? "").trim().toLowerCase();
    return s.isEmpty ? "restaurant" : s.replaceAll(RegExp(r"[^a-z0-9]+"), "-");
  }

  Map<String, dynamic> toMap({required String slug}) => {
    "slug": slug,
    "businessName": businessName,
    "email": email,
    "phone": phone,
    "city": city,
    "state": state,
    "country": country,
    "restaurantType": restaurantType,
    "about": about,
    "updatedAt": FieldValue.serverTimestamp(),
  };

  static UserProfile fromMap(Map<String, dynamic> m) {
    final p = UserProfile();
    p.businessName = m["businessName"];
    p.email = m["email"];
    p.phone = m["phone"];
    p.city = m["city"];
    p.state = m["state"];
    p.country = m["country"];
    p.restaurantType = m["restaurantType"];
    p.about = m["about"];
    return p;
  }
}

class ReservationRequest {
  final String id;
  final String customerName;
  final int guests;
  final DateTime datetime;
  final String? phone;
  final String? notes;
  final RequestStatus status;

  ReservationRequest({
    required this.id,
    required this.customerName,
    required this.guests,
    required this.datetime,
    this.phone,
    this.notes,
    this.status = RequestStatus.pending,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "customerName": customerName,
    "guests": guests,
    "datetime": Timestamp.fromDate(datetime),
    "phone": phone,
    "notes": notes,
    "status": status.name,
  };

  Map<String, dynamic> toReservationMap() => {
    "id": "res_$id",
    "customerName": customerName,
    "guests": guests,
    "datetime": Timestamp.fromDate(datetime),
    "phone": phone,
    "notes": notes,
    "createdAt": FieldValue.serverTimestamp(),
  };

  static ReservationRequest fromMap(Map<String, dynamic> m) => ReservationRequest(
    id: m["id"],
    customerName: m["customerName"],
    guests: m["guests"],
    datetime: (m["datetime"] as Timestamp).toDate(),
    phone: m["phone"],
    notes: m["notes"],
    status: RequestStatus.values.firstWhere(
          (s) => s.name == (m["status"] ?? "pending"),
      orElse: () => RequestStatus.pending,
    ),
  );
}

class Reservation {
  final String id;
  final String customerName;
  final int guests;
  final DateTime datetime;
  final String? phone;
  final String? notes;

  Reservation({
    required this.id,
    required this.customerName,
    required this.guests,
    required this.datetime,
    this.phone,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "customerName": customerName,
    "guests": guests,
    "datetime": Timestamp.fromDate(datetime),
    "phone": phone,
    "notes": notes,
  };

  static Reservation fromMap(Map<String, dynamic> m) => Reservation(
    id: m["id"],
    customerName: m["customerName"],
    guests: m["guests"],
    datetime: (m["datetime"] as Timestamp).toDate(),
    phone: m["phone"],
    notes: m["notes"],
  );
}

class MenuItem {
  final String id;
  final String name;
  final double price;
  final bool available;
  final String? category;

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.available = true,
    this.category,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "name": name,
    "price": price,
    "available": available,
    "category": category,
  };
}

class OfferItem {
  final String id;
  final String title;
  final String description;
  final DateTime validFrom;
  final DateTime validTo;
  final bool active;

  OfferItem({
    required this.id,
    required this.title,
    required this.description,
    required this.validFrom,
    required this.validTo,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "title": title,
    "description": description,
    "validFrom": Timestamp.fromDate(validFrom),
    "validTo": Timestamp.fromDate(validTo),
    "active": active,
  };
}

enum RequestStatus { pending, accepted, declined }