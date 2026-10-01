import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/hotel_api.dart';
import 'app_state.dart';
import 'providers.dart';

/// ربط الدائرة بفندق لدى Amadeus؛ 404 (الإضافة غير منشورة على الخادم) يُعامل كغير مرتبطة حتى لا تتعطل صفحة الدائرة.
final bizHotelProvider = FutureProvider.family<HotelLink, String>((ref, id) async {
  try {
    return await ref.watch(apiClientProvider).bizHotel(id);
  } on ApiException catch (e) {
    if (e.statusCode == 404) return const HotelLink();
    rethrow;
  }
});

/// حالة خدمة الفنادق (مفعّلة؟ بيئة اختبار؟ بطاقة الاختبار للتعبئة التلقائية).
final hotelStatusProvider = FutureProvider<HotelStatus>((ref) => ref.watch(apiClientProvider).hotelStatus());

/// حجوزاتي الفندقية؛ للزائر فارغة بلا طلب، و404 (الإضافة غير منشورة) قائمة فارغة.
final myHotelBookingsProvider = FutureProvider<List<HotelBooking>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  try {
    return await ref.watch(apiClientProvider).myHotelBookings();
  } on ApiException catch (e) {
    if (e.statusCode == 404) return const [];
    rethrow;
  }
});
