import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';

/// مسارات إضافة التجارة (server/commerce.js).
extension CommerceApi on ApiClient {
  Future<Wallet> wallet() async => Wallet.fromJson(await get('/wallet'));
  Future<List<WalletTx>> walletTransactions({DateTime? before}) async =>
      asList(await getList('/wallet/transactions', query: {if (before != null) 'before': before.toUtc().toIso8601String()})).map(WalletTx.fromJson).toList();
  Future<void> walletTopup(int halalas) => post('/wallet/topup', {'amount': halalas});
  Future<void> walletTransfer(String to, int halalas, {String note = ''}) => post('/wallet/transfer', {'to': to, 'amount': halalas, 'note': note});

  Future<List<Event>> events({BBox? bbox, bool mine = false, String? vessel}) async =>
      asList(await getList('/events', query: {if (bbox != null) 'bbox': bbox.query, if (mine) 'mine': '1', if (vessel != null) 'vessel': vessel})).map(Event.fromJson).toList();
  Future<Event> event(String id) async => Event.fromJson(await get('/events/$id'));
  Future<Event> createEvent(Map<String, dynamic> body) async => Event.fromJson(await post('/events', body));
  Future<List<Ticket>> buyTickets(String eventId, String tierId, int qty) async {
    final data = await post('/events/$eventId/tickets', {'tierId': tierId, 'qty': qty});
    return asList(data['data']).map(Ticket.fromJson).toList();
  }
  Future<List<Ticket>> tickets() async => asList(await getList('/tickets')).map(Ticket.fromJson).toList();
  Future<Map<String, dynamic>> checkin(String eventId, String code) => post('/events/$eventId/checkin', {'code': code});
  Future<void> cancelEvent(String id) => post('/events/$id/cancel', const {});

  Future<List<Listing>> market({BBox? bbox, String q = '', String? category}) async =>
      asList(await getList('/market', query: {if (bbox != null) 'bbox': bbox.query, 'q': q, if (category != null) 'category': category})).map(Listing.fromJson).toList();
  Future<List<Listing>> myListings() async => asList(await getList('/market/mine')).map(Listing.fromJson).toList();
  Future<Listing> listing(String id) async => Listing.fromJson(await get('/market/$id'));
  Future<Listing> createListing(Map<String, dynamic> body) async => Listing.fromJson(await post('/market', body));
  Future<void> hideListing(String id) => delete('/market/$id');
  Future<Map<String, dynamic>> order(String listingId, int qty, {String note = ''}) => post('/market/$listingId/order', {'qty': qty, 'note': note});
  Future<List<Order>> orders() async => asList(await getList('/market/orders')).map(Order.fromJson).toList();
  Future<void> deliverOrder(String id) => post('/market/orders/$id/deliver', const {});
  Future<void> cancelOrder(String id) => post('/market/orders/$id/cancel', const {});
}
