import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/profile_v2_providers.dart';
import '../../ui/widgets.dart';
import 'edit_profile_page.dart';
import 'intro_card.dart';
import 'privacy_control_page.dart';

/// بطاقات صاحب الحساب في ماي سبيس تحت بطاقة الملف: التعريف الصوتي/المرئي (أو دعوة لإضافته)، اكتمال الملف بخطواته،
/// وصف «آخر 7 أيام». تختفي كلها حين لا يعرف الخادم v2 بعد.
class OwnerProfileCards extends ConsumerWidget {
  const OwnerProfileCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(myProfileV2Provider).valueOrNull;
    if (p == null) return const SizedBox.shrink();
    final me = ref.watch(appStateProvider.select((s) => s.user));
    final stats = ref.watch(profileStats7Provider).valueOrNull;
    final c = p.completion;
    void edit() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfilePage()));
    return Column(key: const Key('owner-cards'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      if (p.intro != null) ProfileIntroCard(name: p.name.isNotEmpty ? p.name : (me?.nickname ?? ''), intro: p.intro!, owner: true, onChange: edit) else IntroCallToAction(onTap: edit),
      if (c != null && c.steps.isNotEmpty) ...[
        const SizedBox(height: 14),
        JoyCard(
          key: const Key('completion-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('اكتمال الملف ${c.pct}٪', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(c.remaining == 0 ? 'مكتمل' : c.remaining == 1 ? 'خطوة متبقية' : c.remaining == 2 ? 'خطوتان متبقيتان' : '${c.remaining} خطوات متبقية', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: c.pct / 100, minHeight: 8, backgroundColor: Joy.surface2, color: Joy.primary)),
            const SizedBox(height: 8),
            for (final s in c.steps)
              InkWell(
                key: Key('completion-${s.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: s.done ? null : () => _openStep(context, s.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: s.done ? Joy.success : Joy.control),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.label, style: TextStyle(fontSize: 13.5, color: s.done ? Joy.textMuted : Joy.text, decoration: s.done ? TextDecoration.lineThrough : null))),
                    if (!s.done) const Icon(Icons.chevron_left_rounded, size: 18, color: Joy.textMuted),
                  ]),
                ),
              ),
          ]),
        ),
      ],
      if (stats != null) ...[
        const SizedBox(height: 14),
        JoyCard(
          key: const Key('stats7-row'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('آخر 7 أيام', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Row(children: [
              _Stat7('${stats.visits7}', 'زيارات الملف', delta: stats.visitsDeltaPct),
              _Stat7('${stats.messages7}', 'رسائل من الملف'),
              _Stat7('${stats.follows7}', 'متابعون جدد'),
            ]),
          ]),
        ),
      ],
    ]);
  }

  /// كل خطوة تفتح الشاشة التي تُنجزها: التعديل لمعظمها، والتوثيق والتحكم لبريد الدخول.
  void _openStep(BuildContext context, String id) {
    final page = id == 'email' ? const PrivacyControlPage() : const EditProfilePage();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _Stat7 extends StatelessWidget {
  final String value, label;
  final int? delta;
  const _Stat7(this.value, this.label, {this.delta});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5), textAlign: TextAlign.center),
          if (delta != null) Text('${delta! >= 0 ? '+' : ''}$delta٪', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: delta! >= 0 ? Joy.success : Joy.danger)),
        ]),
      );
}
