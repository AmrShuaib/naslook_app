import 'package:flutter/material.dart';

import '../../api/posts_api.dart';
import '../../api/row_api.dart';
import '../business/business_page.dart';
import '../business/offers_page.dart';
import '../events/events_page.dart';
import '../jobs/job_page.dart';
import '../market/listing_page.dart';
import '../posts/post_viewer.dart';

/// رحلة عنصر «الصف» بحسب نوعه: المكان الوحيد الذي يعرف وجهة كل نوع، تستعمله بطاقة الرئيسية وبطاقات «اللحظات» معاً
/// حتى لا تتكرر الرحلات. اللحظة تفتح العارض من حمولتها بلا طلب آخر؛ وتمرير [moments] يسمح بالتمرير بين لحظات القائمة.
void openRowItem(BuildContext context, RowItem it, {List<RowItem> moments = const []}) {
  switch (it.kind) {
    case 'moment':
      if (it.payload.isEmpty) return;
      final list = moments.where((m) => m.kind == 'moment' && m.payload.isNotEmpty).toList();
      final posts = <MapPost>[];
      var initial = 0;
      for (final m in list.isEmpty ? [it] : list) {
        try {
          if (m.id == it.id) initial = posts.length;
          posts.add(MapPost.fromJson(m.payload));
        } catch (_) {
          // حمولة ناقصة من عنصر آخر لا تمنع فتح المختار
        }
      }
      if (posts.isEmpty) return;
      // عبر open: يفتح عناصر الصوت داخل هذه اللمسة فتبدأ اللحظة الأولى بصوتها على سفاري iOS
      PostViewerPage.open(context, posts, index: initial);
    case 'offer':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleOffersPage(bizId: it.refId, title: it.who.isEmpty ? null : it.who)));
    case 'event':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: it.refId)));
    case 'job':
      // الوظيفة تُفتح بمعرّفها (id)؛ refId للوظيفة هو الدائرة صاحبتها (للدبوس والتجميع) لا الوظيفة
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobPage(id: it.id)));
    case 'listing':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(it.refId)));
    case 'circle':
      openBusiness(context, it.refId);
  }
}
