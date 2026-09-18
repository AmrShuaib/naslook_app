// بطاقة البيانات الشخصية الكاملة لمستخدم في لوحة الإدارة: كل حقول حسابه في النواة وملفه، بُرُد الدخول وحالة تأكيدها،
// عبارة الاسترداد، الجلسات والأجهزة، وأعداد نشاطه. الحقول تأتي من الخادم بأسماء أعمدتها، وتُعرض بعناوين عربية
// للمعروف منها وبأسمائها الخام لغيرها حتى لا يضيع أي حقل.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/admin_api.dart';
import '../../core/app_theme.dart';
import '../../ui/widgets.dart';

const _labels = <String, String>{
  'id': 'المعرّف', 'user_id': 'المعرّف', 'nickname': 'اسم المستخدم', 'handle': 'اسم المستخدم', 'display_name': 'الاسم الظاهر', 'name': 'الاسم',
  'avatar_url': 'صورة الحساب', 'account_type': 'نوع الحساب', 'is_public': 'الملف عام', 'bio': 'النبذة', 'skills': 'المهارات', 'hobbies': 'الهوايات',
  'looking_for': 'يبحث عن', 'lookingfor': 'يبحث عن', 'offerings': 'يقدّم', 'voice_intro_url': 'مقدمة صوتية', 'visibility': 'إعدادات الظهور',
  'phone': 'الجوال', 'mobile': 'الجوال', 'city': 'المدينة', 'district': 'الحي', 'country': 'الدولة', 'gender': 'الجنس', 'birth_date': 'تاريخ الميلاد', 'birthdate': 'تاريخ الميلاد',
  'lang': 'اللغة', 'locale': 'اللغة', 'created_at': 'تاريخ التسجيل', 'updated_at': 'آخر تحديث', 'last_seen_at': 'آخر ظهور', 'last_seen': 'آخر ظهور', 'last_active_at': 'آخر نشاط',
  'deleted_at': 'تاريخ الحذف', 'is_admin': 'مدير في النواة', 'role': 'الدور', 'restricted': 'مقيَّد', 'push_preview': 'معاينة الإشعارات', 'hide_after_hours': 'إخفاء الحضور بعد (ساعة)',
  'online': 'متصل الآن', 'email': 'البريد', 'verified': 'مؤكَّد', 'status': 'الحالة', 'timezone': 'المنطقة الزمنية', 'referrer': 'المُحيل', 'ip': 'عنوان الشبكة', 'last_ip': 'آخر عنوان شبكة',
};
const _order = ['id', 'user_id', 'nickname', 'handle', 'display_name', 'name', 'account_type', 'is_public', 'bio', 'skills', 'hobbies', 'looking_for', 'lookingfor', 'offerings', 'voice_intro_url',
  'phone', 'mobile', 'city', 'district', 'country', 'gender', 'birth_date', 'birthdate', 'lang', 'locale', 'created_at', 'updated_at', 'last_seen_at', 'last_seen', 'last_active_at', 'deleted_at', 'role', 'is_admin', 'restricted', 'avatar_url'];
const _countLabels = <String, String>{
  'listings': 'عروض في السوق', 'marketOrders': 'مشتريات من السوق', 'bizOrders': 'طلبات دوائر', 'circles': 'دوائر يملكها', 'mapPosts': 'منشورات خريطة', 'communityPosts': 'منشورات مجتمع',
  'contacts': 'جهات اتصال', 'memberships': 'عضويات دوائر', 'notifications': 'إشعارات', 'pushSubscriptions': 'أجهزة إشعارات', 'reportsMade': 'بلاغات قدّمها', 'blocks': 'حظر',
};

String adminDate(DateTime? t) {
  if (t == null) return '';
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}/${two(l.month)}/${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// نص معروض لقيمة حقل كما جاءت من الخادم
String adminValueText(String key, Object? v) {
  if (v == null) return '';
  if (v is bool) return v ? 'نعم' : 'لا';
  if (v is List) return v.map((e) => e.toString()).where((e) => e.isNotEmpty).join('، ');
  if (v is Map) return v.entries.map((e) => '${_labels[e.key.toString()] ?? e.key}: ${adminValueText(e.key.toString(), e.value)}').join(' · ');
  final s = v.toString().trim();
  if (s.isEmpty) return '';
  if (key == 'account_type') return switch (s) { 'personal' => 'شخصي', 'business' => 'تجاري', _ => s };
  if (key == 'gender') return switch (s) { 'male' || 'm' => 'ذكر', 'female' || 'f' => 'أنثى', _ => s };
  if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) { final t = DateTime.tryParse(s); if (t != null) return '${adminDate(t)} (${timeAgo(t)})'; }
  if (key.endsWith('_url')) return 'موجودة';
  return s;
}

class AdminPersonalCard extends StatelessWidget {
  final AdminUserDetail detail;
  const AdminPersonalCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final all = <String, Object?>{...detail.profile, ...detail.personal};
    final shown = <String>{};
    final rows = <Widget>[];
    void add(String key, Object? v, {bool copy = false}) {
      final text = adminValueText(key, v);
      if (text.isEmpty) return;
      rows.add(_Row(label: _labels[key] ?? key, value: text, copy: copy, valueKey: 'personal-$key'));
    }
    for (final k in _order) { if (!all.containsKey(k) || shown.contains(k)) continue; shown.add(k); add(k, all[k], copy: k == 'id' || k == 'user_id' || k == 'phone' || k == 'mobile'); }
    // الملف قد يحمل updated_at مختلفاً عن الحساب
    if (detail.profile['updated_at'] != null && detail.personal.containsKey('updated_at') && detail.profile['updated_at'] != detail.personal['updated_at']) {
      rows.add(_Row(label: 'آخر تحديث للملف', value: adminValueText('updated_at', detail.profile['updated_at']), valueKey: 'personal-profile-updated'));
    }
    final rest = all.keys.where((k) => !shown.contains(k)).toList()..sort();
    final other = <Widget>[for (final k in rest) if (adminValueText(k, all[k]).isNotEmpty) _Row(label: _labels[k] ?? k, value: adminValueText(k, all[k]), valueKey: 'personal-$k')];
    final counts = detail.counts.entries.where((e) => e.value != null).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      JoyCard(key: const Key('personal-card'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // البريد أولاً لأنه أكثر ما يُسأل عنه
        const _Sub('بريد الدخول'),
        if (detail.emails.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('لا يوجد بريد دخول مرتبط بهذا الحساب', key: Key('personal-no-email'), style: TextStyle(color: Joy.textMuted, fontSize: 13))),
        for (final e in detail.emails)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            const Icon(Icons.alternate_email_rounded, size: 18, color: Joy.textMuted), const SizedBox(width: 8),
            Expanded(child: Text(e.email, key: const Key('personal-email'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), textDirection: TextDirection.ltr)),
            _Badge(e.verified ? 'مؤكَّد' : 'غير مؤكَّد', e.verified ? Joy.success : Joy.warning),
            IconButton(tooltip: 'نسخ', visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () => _copy(context, e.email)),
          ])),
        for (final e in detail.emails) if (e.verifiedAt != null || e.createdAt != null)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${e.verifiedAt != null ? 'أُكِّد ${adminDate(e.verifiedAt)}' : 'لم يُؤكَّد بعد'}${e.createdAt != null ? ' · رُبط ${adminDate(e.createdAt)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        const Divider(height: 16),
        const _Sub('الحساب والملف'),
        ...rows,
        if (other.isNotEmpty) ...[const Divider(height: 16), const _Sub('حقول أخرى'), ...other],
        const Divider(height: 16),
        const _Sub('الأمان والجلسات'),
        _Row(label: 'عبارة الاسترداد', value: detail.hasRecovery ? 'محفوظة${detail.recoverySource != null ? ' (${detail.recoverySource == 'register' ? 'منذ التسجيل' : detail.recoverySource})' : ''}' : 'غير محفوظة', valueKey: 'personal-recovery'),
        if (detail.sessions != null) _Row(label: 'الجلسات المفتوحة', value: '${detail.sessions!.count}${detail.sessions!.last != null ? ' · آخرها ${adminDate(detail.sessions!.last)}' : ''}', valueKey: 'personal-sessions'),
        if (detail.sessions != null && detail.sessions!.agents.isNotEmpty) _Row(label: 'الأجهزة', value: detail.sessions!.agents.map(_shortAgent).join('، '), valueKey: 'personal-agents'),
        if (counts.isNotEmpty) ...[
          const Divider(height: 16),
          const _Sub('نشاطه في المنصة'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final c in counts) _Badge('${_countLabels[c.key] ?? c.key} ${c.value}', Joy.text, bg: Joy.bg)]),
          const SizedBox(height: 4),
        ],
      ])),
    ]);
  }

  static String _shortAgent(String a) {
    if (a.contains('iPhone')) return 'آيفون';
    if (a.contains('Android')) return 'أندرويد';
    if (a.contains('Macintosh')) return 'ماك';
    if (a.contains('Windows')) return 'ويندوز';
    return a.length > 24 ? '${a.substring(0, 24)}…' : a;
  }

  static Future<void> _copy(BuildContext context, String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (context.mounted) toast(context, 'نُسخ');
  }
}

class _Sub extends StatelessWidget {
  final String t;
  const _Sub(this.t);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Joy.textMuted)));
}

class _Row extends StatelessWidget {
  final String label, value, valueKey;
  final bool copy;
  const _Row({required this.label, required this.value, required this.valueKey, this.copy = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 13))),
          Expanded(child: SelectableText(value, key: Key(valueKey), style: const TextStyle(fontSize: 13.5))),
          if (copy) InkWell(onTap: () => AdminPersonalCard._copy(context, value), child: const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.copy_rounded, size: 16, color: Joy.textMuted))),
        ]),
      );
}

class _Badge extends StatelessWidget {
  final String t;
  final Color c;
  final Color? bg;
  const _Badge(this.t, this.c, {this.bg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg ?? c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
