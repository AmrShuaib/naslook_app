import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/saved_search_api.dart';
import 'app_state.dart';

/// بحوث المستخدم المحفوظة.
final savedSearchesProvider = FutureProvider<List<SavedSearch>>((ref) => ref.watch(apiClientProvider).savedSearches());
