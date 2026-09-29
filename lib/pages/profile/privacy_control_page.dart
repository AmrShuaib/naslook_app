import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/naslife_api.dart';
import '../../api/profile_v2_api.dart';
import '../../api/profile_v2_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/profile_v2_providers.dart';
import '../../state/providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart' show errText;
import '../myspace/safety_page.dart';

/// «التوثيق والتحكم»: درجة التوثيق (بريد، جوال قريباً، نفاذ قريباً)، من يراسلني (الجميع/الأصدقاء/لا أحد)،
/// ما يظهر في ملفي (متصل الآن، المدينة، التعريف، الأصدقاء، ملف عام)، والأمان (المحظورون، المكتومون، الأجهزة قريباً).
class PrivacyControlPage extends ConsumerStatefulWidget {
  const PrivacyControlPage({super.key});
  @override
  ConsumerState<PrivacyControlPage> createState() => _PrivacyControlPageState();
}

class _PrivacyControlPageState extends ConsumerState<PrivacyControlPage> {
  // نسخة محلية متفائلة من الإعدادات حتى يصل ردّ الخادم
  ProfileSettings? _local;
  bool? _publicLocal;

  @override
  Widget build(BuildContext context) {
    final v2 = ref.watch(myProfileV2Provider);
    final core = ref.watch(profileProvider);
    final p = v2.valueOrNull;
    final s = _local ?? p?.settings;
    final hasV2 = p != null;
    final isPublic = _publicLocal ?? core.valueOrNull?.isPublic ?? true;
    final blockedCount = ref.watch(blockedUsersProvider).valueOrNull?.length;
    final mutedCount = ref.watch(mutesProvider).valueOrNull?.length;
    final emailVerified = p?.trust.emailVerified ?? false;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('التوثيق والتحكم')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        const SectionTitle('درجة التوثيق'),
        JoyCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              key: const Key('verify-email'),
              leading: Icon(Icons.mail_outline_rounded, color: emailVerified ? Joy.success : Joy.textMuted),
              title: const Text('البريد الإلكتروني'),
              subtitle: Text(emailVerified ? 'موثّق' : 'غير موثّق بعد · من «حسابي» في ماي سبيس'),
              trailing: emailVerified ? const Icon(Icons.verified_rounded, color: Joy.success) : null,
            ),
            const Divider(indent: 16, endIndent: 16),
            const ListTile(key: Key('verify-phone'), leading: Icon(Icons.phone_iphone_rounded, color: Joy.textMuted), title: Text('رقم الجوال'), subtitle: Text('توثيق الجوال يظهر علامة التوثيق بجانب اسمك'), trailing: _Soon()),
            const Divider(indent: 16, endIndent: 16),
            const ListTile(key: Key('verify-id'), leading: Icon(Icons.badge_outlined, color: Joy.textMuted), title: Text('الهوية (نفاذ)'), subtitle: Text('شارة «موثّق بالهوية» للبائعين ومقدمي الخدمات'), trailing: _Soon()),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('من يراسلني'),
        JoyCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: const Key('msg-policy'),
              segments: const [
                ButtonSegment(value: 'all', label: Text('الجميع')),
                ButtonSegment(value: 'friends', label: Text('الأصدقاء')),
                ButtonSegment(value: 'none', label: Text('لا أحد')),
              ],
              selected: {s?.msgPolicy ?? 'all'},
              showSelectedIcon: false,
              onSelectionChanged: hasV2 ? (v) => _put({'msgPolicy': v.first}, (x) => x.copyWith(msgPolicy: v.first)) : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (s?.msgPolicy ?? 'all') {
              'friends' => 'أصدقاؤك فقط يستطيعون مراسلتك؛ زر «مراسلة» يختفي من ملفك لغيرهم.',
              'none' => 'لا أحد يستطيع بدء محادثة معك من ملفك.',
              _ => 'أي مستخدم يستطيع مراسلتك؛ الرسائل الأولى من غير الأصدقاء تصل إلى تبويب «الطلبات».',
            },
            style: const TextStyle(color: Joy.textMuted, fontSize: 12.5),
          ),
          if (!hasV2) const Padding(padding: EdgeInsets.only(top: 6), child: Text('تُفعَّل بعد تحديث الخادم', style: TextStyle(color: Joy.warning, fontSize: 12))),
        ])),
        const SizedBox(height: 14),
        const SectionTitle('ما يظهر في ملفي'),
        JoyCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(key: const Key('show-online'), value: s?.showOnline ?? true, onChanged: hasV2 ? (v) => _put({'showOnline': v}, (x) => x.copyWith(showOnline: v)) : null, title: const Text('الحالة «متصل الآن»'), subtitle: const Text('يراها زوار ملفك'), secondary: const Icon(Icons.circle, color: Joy.success, size: 14)),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(key: const Key('show-city'), value: s?.showCity ?? true, onChanged: hasV2 ? (v) => _put({'showCity': v}, (x) => x.copyWith(showCity: v)) : null, title: const Text('المدينة والحي'), subtitle: Text(p != null && p.place.isNotEmpty ? p.place : 'لم تحدّد مدينتك بعد'), secondary: const Icon(Icons.place_outlined, color: Joy.text)),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(
              key: const Key('intro-visibility'),
              value: (s?.introVisibility ?? 'all') == 'all',
              onChanged: hasV2 ? (v) => _put({'introVisibility': v ? 'all' : 'friends'}, (x) => x.copyWith(introVisibility: v ? 'all' : 'friends')) : null,
              title: const Text('التعريف الصوتي أو المرئي'),
              subtitle: Text((s?.introVisibility ?? 'all') == 'all' ? 'للجميع · أطفئه ليظهر للأصدقاء فقط' : 'للأصدقاء فقط'),
              secondary: const Icon(Icons.mic_none_rounded, color: Joy.text),
            ),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(key: const Key('show-friends'), value: s?.showFriends ?? false, onChanged: hasV2 ? (v) => _put({'showFriends': v}, (x) => x.copyWith(showFriends: v)) : null, title: const Text('قائمة الأصدقاء'), subtitle: Text((s?.showFriends ?? false) ? 'ظاهرة لزوار ملفك' : 'مخفية عن الجميع الآن'), secondary: const Icon(Icons.people_outline_rounded, color: Joy.text)),
            const Divider(indent: 16, endIndent: 16),
            const ListTile(leading: Icon(Icons.badge_outlined, color: Joy.text), title: Text('الرقم SA'), subtitle: Text('للأصدقاء فقط دائماً، ويُنسخ من بطاقة الدردشة'), trailing: Text('للأصدقاء', style: TextStyle(color: Joy.textMuted, fontSize: 12))),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(
              key: const Key('profile-public'),
              value: isPublic,
              onChanged: core.valueOrNull == null ? null : _setPublic,
              title: const Text('ملف عام'),
              subtitle: const Text('غير العام يخفي التفاصيل والمنشورات عن غير الأصدقاء ويخرجك من البحث'),
              secondary: const Icon(Icons.shield_outlined, color: Joy.text),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('الأمان'),
        JoyCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(key: const Key('safety-blocked'), leading: const Icon(Icons.block_rounded, color: Joy.text), title: const Text('المحظورون'), subtitle: Text(blockedCount == null ? '' : _count(blockedCount, 'حساب', 'حسابان', 'حسابات')), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafetyPage()))),
            const Divider(indent: 16, endIndent: 16),
            ListTile(key: const Key('safety-muted'), leading: const Icon(Icons.volume_off_outlined, color: Joy.text), title: const Text('المحادثات الصامتة'), subtitle: Text(mutedCount == null ? '' : _count(mutedCount, 'محادثة', 'محادثتان', 'محادثات')), trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafetyPage()))),
            const Divider(indent: 16, endIndent: 16),
            const ListTile(key: Key('safety-devices'), leading: Icon(Icons.devices_rounded, color: Joy.textMuted), title: Text('الأجهزة المسجّل دخولها'), trailing: _Soon()),
          ]),
        ),
      ]),
    );
  }

  static String _count(int n, String one, String two, String many) => n == 0 ? 'لا شيء' : n == 1 ? '$one واحد' : n == 2 ? two : '$n $many';

  Future<void> _put(Map<String, dynamic> patch, ProfileSettings Function(ProfileSettings) apply) async {
    final before = _local ?? ref.read(myProfileV2Provider).valueOrNull?.settings ?? const ProfileSettings();
    setState(() => _local = apply(before));
    try {
      final p = await ref.read(apiClientProvider).updateProfileV2(patch);
      if (mounted) setState(() => _local = p.settings ?? _local);
      ref.invalidate(myProfileV2Provider);
    } catch (e) {
      if (mounted) {
        setState(() => _local = before);
        toast(context, errText(e), error: true);
      }
    }
  }

  Future<void> _setPublic(bool v) async {
    setState(() => _publicLocal = v);
    try {
      await ref.read(apiClientProvider).updateProfile({'isPublic': v});
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _publicLocal = !v);
        toast(context, errText(e), error: true);
      }
    }
  }
}

class _Soon extends StatelessWidget {
  const _Soon();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)), child: const Text('قريباً', style: TextStyle(color: Joy.textMuted, fontSize: 12, fontWeight: FontWeight.w600)));
}
