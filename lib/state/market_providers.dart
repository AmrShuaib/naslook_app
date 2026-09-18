import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/commerce_api.dart';
import '../api/commerce_models.dart';
import 'app_state.dart';
import 'providers.dart';

/// عروض السوق ذات الموقع ضمن حدود الخريطة الحالية (طبقة «السوق» على الخريطة)
final mapMarketProvider = FutureProvider<List<Listing>>((ref) async => (await ref.watch(apiClientProvider).market(bbox: ref.watch(bboxProvider), limit: 100)).where((l) => l.lat != null && l.lng != null).toList());
