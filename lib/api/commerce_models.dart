import 'models.dart';

String money(int halalas) {
  final v = halalas / 100;
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return '$s ر.س';
}

Map<String, dynamic> _m(dynamic v) => asMap(v);
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

class Wallet {
  final int balance;
  final int points;
  final int upcomingTickets;
  final bool testTopup;
  final List<WalletTx> recent;
  const Wallet({required this.balance, required this.points, required this.upcomingTickets, required this.testTopup, required this.recent});
  factory Wallet.fromJson(Map m) => Wallet(
        balance: _i(m['balance']), points: _i(m['points']), upcomingTickets: _i(m['upcomingTickets']), testTopup: m['testTopup'] == true,
        recent: asList(m['recent']).map(WalletTx.fromJson).toList(),
      );
}

class WalletTx {
  final String id;
  final String kind;
  final int amount;
  final Person? peer;
  final String? ref;
  final String? note;
  final DateTime? createdAt;
  const WalletTx({required this.id, required this.kind, required this.amount, this.peer, this.ref, this.note, this.createdAt});
  factory WalletTx.fromJson(Map m) => WalletTx(
        id: m['id'].toString(), kind: m['kind']?.toString() ?? '', amount: _i(m['amount']),
        peer: m['peer'] is Map ? Person.fromJson(_m(m['peer'])) : null, ref: m['ref']?.toString(), note: m['note']?.toString(), createdAt: _t(m['createdAt']),
      );
  bool get positive => amount > 0;
  String get label => switch (kind) {
        'topup' => 'شحن', 'credit' => 'إضافة رصيد', 'debit' => 'خصم', 'transfer_in' => 'تحويل وارد', 'transfer_out' => 'تحويل صادر',
        'ticket' => 'تذاكر', 'ticket_sale' => 'بيع تذاكر', 'market' => 'شراء من السوق', 'market_sale' => 'بيع في السوق',
        'refund' => 'استرداد', 'refund_out' => 'إعادة مبلغ', _ => kind };
}

class TicketTier {
  final String id, name, description;
  final int price, quantity, sold, left;
  const TicketTier({required this.id, required this.name, required this.description, required this.price, required this.quantity, required this.sold, required this.left});
  factory TicketTier.fromJson(Map m) => TicketTier(id: m['id'].toString(), name: m['name']?.toString() ?? '', description: m['description']?.toString() ?? '', price: _i(m['price']), quantity: _i(m['quantity']), sold: _i(m['sold']), left: _i(m['left']));
}

class Event {
  final String id, title, description;
  final Person host;
  final String? vesselId, placeName;
  final DateTime? startsAt, endsAt;
  final double? lat, lng;
  final bool cancelled, isHost;
  final int going, myTickets;
  final List<TicketTier> tiers;
  const Event({required this.id, required this.title, required this.description, required this.host, this.vesselId, this.placeName, this.startsAt, this.endsAt, this.lat, this.lng, this.cancelled = false, this.isHost = false, this.going = 0, this.myTickets = 0, this.tiers = const []});
  factory Event.fromJson(Map m) => Event(
        id: m['id'].toString(), title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', host: Person.fromJson(_m(m['host'])),
        vesselId: m['vesselId']?.toString(), placeName: m['placeName']?.toString(), startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']),
        lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), cancelled: m['cancelled'] == true, isHost: m['isHost'] == true,
        going: _i(m['going']), myTickets: _i(m['myTickets']), tiers: asList(m['tiers']).map(TicketTier.fromJson).toList(),
      );
  int get minPrice => tiers.isEmpty ? 0 : tiers.map((t) => t.price).reduce((a, b) => a < b ? a : b);
}

class Ticket {
  final String id, code, status, eventId, title, tier;
  final int paid;
  final DateTime? startsAt, createdAt, usedAt;
  final String? placeName;
  const Ticket({required this.id, required this.code, required this.status, required this.eventId, required this.title, required this.tier, required this.paid, this.startsAt, this.createdAt, this.usedAt, this.placeName});
  factory Ticket.fromJson(Map m) => Ticket(id: m['id'].toString(), code: m['code']?.toString() ?? '', status: m['status']?.toString() ?? 'valid', eventId: m['eventId'].toString(), title: m['title']?.toString() ?? '', tier: m['tier']?.toString() ?? '', paid: _i(m['paid']), startsAt: _t(m['startsAt']), createdAt: _t(m['createdAt']), usedAt: _t(m['usedAt']), placeName: m['placeName']?.toString());
  bool get upcoming => status == 'valid' && (startsAt == null || startsAt!.isAfter(DateTime.now().subtract(const Duration(hours: 6))));
}

class Listing {
  final String id, kind, category, title, description, status;
  final Person seller;
  final int price;
  final String? imageUrl, placeName;
  final double? lat, lng;
  final bool mine;
  final DateTime? createdAt;
  const Listing({required this.id, required this.kind, required this.category, required this.title, required this.description, required this.status, required this.seller, required this.price, this.imageUrl, this.placeName, this.lat, this.lng, this.mine = false, this.createdAt});
  factory Listing.fromJson(Map m) => Listing(
        id: m['id'].toString(), kind: m['kind']?.toString() ?? 'product', category: m['category']?.toString() ?? 'other', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        status: m['status']?.toString() ?? 'active', seller: Person.fromJson(_m(m['seller'])), price: _i(m['price']), imageUrl: m['imageUrl']?.toString(), placeName: m['placeName']?.toString(),
        lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), mine: m['mine'] == true, createdAt: _t(m['createdAt']),
      );
}

class Order {
  final String id, listingId, title, status, note;
  final String? imageUrl;
  final int qty, total;
  final Person buyer, seller;
  final bool mineAsSeller;
  final DateTime? createdAt;
  const Order({required this.id, required this.listingId, required this.title, required this.status, required this.note, this.imageUrl, required this.qty, required this.total, required this.buyer, required this.seller, required this.mineAsSeller, this.createdAt});
  factory Order.fromJson(Map m) => Order(id: m['id'].toString(), listingId: m['listingId'].toString(), title: m['title']?.toString() ?? '', status: m['status']?.toString() ?? '', note: m['note']?.toString() ?? '', imageUrl: m['imageUrl']?.toString(), qty: _i(m['qty']), total: _i(m['total']), buyer: Person.fromJson(_m(m['buyer'])), seller: Person.fromJson(_m(m['seller'])), mineAsSeller: m['mineAsSeller'] == true, createdAt: _t(m['createdAt']));
}

const marketCategories = {
  'coffee': 'مقاهي', 'food': 'طعام', 'photo': 'تصوير', 'gifts': 'هدايا', 'handmade': 'أعمال يدوية', 'delivery': 'توصيل', 'services': 'خدمات', 'other': 'أخرى',
};
