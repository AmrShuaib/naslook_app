import 'package:flutter/material.dart';

import '../../api/posts_api.dart';
import 'composer/capture_page.dart';
import 'composer/composer_draft.dart';
import 'composer/edit_page.dart';
import 'composer/publish_page.dart';

export 'composer/composer_draft.dart' show ComposerDraft, Destination;
export 'composer/publish_page.dart' show PublishOutcome;

/// محرّر المحتوى: الكاميرا أولاً (صورة، فيديو، نص)، ثم «راجع وعدّل» بأربع أدوات، ثم شاشة نشر واحدة تختار فيها أين يظهر
/// (الخريطة، دائرة، السوق) وكم يبقى. الشاشات الثلاث تتبادل [ComposerDraft] واحداً، والرجوع من أي شاشة يعيدك خطوة.
class PostComposerPage {
  PostComposerPage._();

  /// يفتح المحرّر ويعيد المنشور إن نُشر على الخريطة (أو عُدّل)، وnull عند الإلغاء أو النشر في وجهة أخرى.
  static Future<MapPost?> open(BuildContext context, {required double lat, required double lng, String? placeName, MapPost? edit}) async {
    final r = await openFull(context, lat: lat, lng: lng, placeName: placeName, edit: edit);
    return r?.post;
  }

  /// كـ[open] لكنه يعيد نتيجة النشر كاملة (الوجهة والمعرّفات).
  static Future<PublishOutcome?> openFull(BuildContext context, {required double lat, required double lng, String? placeName, MapPost? edit}) async {
    final nav = Navigator.of(context);
    final d = ComposerDraft(lat: lat, lng: lng, placeName: placeName ?? '', editing: edit);
    if (edit != null) {
      d
        ..kind = edit.kind == 'audio' ? 'text' : edit.kind
        ..board = edit.bg ?? '#FFFFFF'
        ..overlays = List.of(edit.overlays)
        ..caption = edit.caption
        ..placeName = edit.placeName ?? placeName ?? ''
        ..tag = edit.tag
        ..title = edit.title
        ..price = edit.price == null ? '' : (edit.price! % 100 == 0 ? '${edit.price! ~/ 100}' : (edit.price! / 100).toStringAsFixed(2))
        ..ctaType = edit.cta?.type
        ..ctaValue = edit.cta?.value ?? ''
        ..ctaLabel = edit.cta?.label ?? '';
    } else {
      await restoreComposerDraft(d);
    }
    var stage = edit == null ? 0 : 1;
    while (true) {
      if (!context.mounted) return null;
      switch (stage) {
        case 0:
          final r = await nav.push<ComposerDraft>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => CapturePage(draft: d)));
          if (r == null) return null;
          stage = 1;
        case 1:
          final r = await nav.push<int>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditPage(draft: d)));
          if (r == 1) {
            stage = 2;
          } else if (edit != null) {
            return null;
          } else {
            stage = 0;
          }
        default:
          final r = await nav.push<PublishOutcome>(MaterialPageRoute(builder: (_) => PublishPage(draft: d)));
          if (r != null) return r;
          stage = 1;
      }
    }
  }
}
