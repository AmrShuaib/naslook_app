import 'package:flutter/material.dart';

import '../../../api/profile_v2_models.dart';
import '../../../core/app_theme.dart';

/// بديل المؤلّف حين يمنع الطرف الآخر الرسائل الجديدة («من يراسلني»): السبب بوضوح، و«إضافة صديق» لسياسة الأصدقاء.
/// يحلّ محل المؤلّف كله (المرفقات والتسجيل والردود المقترحة) لأن النواة لا تفحص السياسة عند الإرسال.
class MessageGateNotice extends StatelessWidget {
  final MessageGate gate;
  /// يرسل طلب الصداقة؛ null يخفي الزر (السبب ليس الأصدقاء).
  final VoidCallback? onAddFriend;
  /// أرسلتُ الطلب (الآن أو سابقاً: هو في جهات اتصالي) فننتظر قبوله بدل زر لا يفعل جديداً.
  final bool requested;
  final bool busy;
  const MessageGateNotice({super.key, required this.gate, this.onAddFriend, this.requested = false, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final friends = gate.friendsOnly;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('msg-gate'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(gate.reason == 'blocked' ? Icons.block_rounded : Icons.lock_outline_rounded, size: 20, color: Joy.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(gate.notice, key: const Key('msg-gate-text'), style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
          ]),
          if (friends) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(requested ? 'أُرسل طلب الصداقة؛ تستطيع مراسلته بعد قبوله' : 'أضفه صديقاً وتستطيع مراسلته حين يقبل',
                    key: const Key('msg-gate-hint'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
              ),
            ),
            if (!requested && onAddFriend != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('msg-gate-add-friend'),
                  onPressed: busy ? null : onAddFriend,
                  icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('إضافة صديق'),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
