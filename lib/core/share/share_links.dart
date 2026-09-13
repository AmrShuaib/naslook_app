import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/client.dart';
import '../../ui/widgets.dart';
import '../app_theme.dart';
import 'share_stub.dart' if (dart.library.js_interop) 'share_web.dart' as impl;

/// رابط عام وصل عند الإقلاع: دائرة (`/c/<id>`) أو حساب (`/u/<نك نيم>`)، بالمسار أو بالجزء (`#/c/…`).
class PendingLink {
  final String kind; // circle | user
  final String value;
  const PendingLink(this.kind, this.value);
  bool get isCircle => kind == 'circle';
  @override
  String toString() => '$kind:$value';
}

/// الرابط المعلّق حتى يُفتح بعد الدخول أو كزائر.
PendingLink? pendingLink;

final _circleRe = RegExp(r'^/?c/([a-z0-9][a-z0-9-]{1,63})/?$');
final _userRe = RegExp(r'^/?u/([^/?#]{2,40})/?$');

PendingLink? parsePendingLink(Uri uri) {
  for (final s in [uri.path, uri.fragment]) {
    final m = _circleRe.firstMatch(s);
    if (m != null) return PendingLink('circle', m.group(1)!);
    final u = _userRe.firstMatch(s);
    if (u != null) return PendingLink('user', Uri.decodeComponent(u.group(1)!));
  }
  return null;
}

/// يُستدعى في main() قبل أن يعيد محرك Flutter كتابة الرابط.
void capturePendingLink([Uri? uri]) {
  pendingLink = parsePendingLink(uri ?? Uri.base);
}

/// أصل الروابط العامة: أصل الموقع على الويب (إلا محلياً)، وإلا الموقع الرسمي.
String publicOrigin() {
  if (kIsWeb) {
    final o = Uri.base.origin;
    if (!o.contains('localhost') && !o.contains('127.0.0.1')) return o;
  }
  return ApiClient.defaultBase.replaceFirst(RegExp(r'/+$'), '');
}

String circleLink(String id) => '${publicOrigin()}/c/$id';
String profileLink(String nickname) => '${publicOrigin()}/u/${Uri.encodeComponent(nickname)}';

/// ورقة مشاركة: رمز QR والرابط وأزرار المشاركة الأصلية والنسخ.
Future<void> shareLink(BuildContext context, {required String title, required String url, String subtitle = 'على ناس لايف'}) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Joy.line)),
              child: QrImageView(key: const Key('share-qr'), data: url, size: 168),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.link_rounded, size: 18, color: Joy.textMuted),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(url, key: const Key('share-url'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('share-native'),
                onPressed: () async {
                  final ok = await impl.nativeShare(title: title, text: '$title $subtitle', url: url);
                  if (!ctx.mounted) return;
                  if (!ok) {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (ctx.mounted) toast(ctx, 'نُسخ الرابط، الصقه حيث تريد');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('مشاركة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('share-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (ctx.mounted) {
                    toast(ctx, 'نُسخ الرابط');
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرابط'),
              ),
            ),
          ]),
        ]),
      ),
    );
