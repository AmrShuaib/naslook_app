import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import 'user_profile_page.dart';

final userByHandleProvider = FutureProvider.family<Person, String>((ref, handle) => ref.watch(apiClientProvider).userByHandle(handle));

/// ملف عام يُفتح من رابط `naslife.app/u/<نك نيم>`: يحلّ النك نيم إلى حساب ثم يعرض صفحة الملف.
class PublicProfilePage extends ConsumerWidget {
  final String handle;
  const PublicProfilePage({super.key, required this.handle});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByHandleProvider(handle));
    return user.when(
      loading: () => const Scaffold(backgroundColor: Joy.bg, body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: Text(handle)),
        body: e is ApiException && e.statusCode == 404
            ? const EmptyState(icon: Icons.person_off_outlined, title: 'الحساب غير موجود', subtitle: 'تأكد من كتابة النك نيم في الرابط')
            : ErrorState(e, onRetry: () => ref.invalidate(userByHandleProvider(handle))),
      ),
      data: (p) => UserProfilePage(person: p),
    );
  }
}
