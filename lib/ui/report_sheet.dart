// ورقة الإبلاغ الموحّدة وقائمة «إبلاغ/حظر» لكل محتوى ينشره المستخدمون (قاعدة أبل 1.2): أسباب جاهزة لا تتطلب كتابة،
// ملاحظة اختيارية، وخيار «حظر الناشر أيضاً». البلاغ عن المحتوى يذهب إلى /safety/report، وعن الشخص إلى /reports في النواة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../api/naslife_api.dart';
import '../api/safety_api.dart';
import '../core/app_theme.dart';
import '../state/app_state.dart';
import '../state/safety_providers.dart';
import 'widgets.dart';

/// أسباب البلاغ الجاهزة (السبب يكفي وحده؛ الملاحظة اختيارية).
const kReportReasons = [
  'محتوى مسيء أو كراهية',
  'تحرش أو تنمر',
  'محتوى جنسي',
  'عنف',
  'احتيال أو نصب',
  'إزعاج أو سبام',
  'انتحال شخصية',
  'أخرى',
];

/// نوع البلاغ عن شخص (يذهب إلى بلاغات المستخدمين في النواة لا إلى بلاغات المحتوى).
const kReportUser = 'user';

/// نتيجة البلاغ: هل أُخفي المحتوى تلقائياً، وهل حُظر الناشر.
class ReportOutcome {
  final bool sent, hidden, blocked;
  const ReportOutcome({this.sent = false, this.hidden = false, this.blocked = false});
}

/// اختيار المستخدم في الورقة.
class _Choice {
  final String reason, note;
  final bool block;
  const _Choice(this.reason, this.note, this.block);
  String get text => note.isEmpty ? reason : '$reason: $note';
}

/// رسالة مفهومة لأخطاء البلاغ المعروفة.
String reportErrorText(Object e) {
  final code = e is ApiException ? (e.body ?? const {})['error']?.toString() : null;
  return switch (code) {
    'own-content' => 'لا يمكنك الإبلاغ عن محتواك',
    'not-found' => 'لم يعد هذا المحتوى موجوداً',
    'bad-target' || 'bad-id' => 'لا يمكن الإبلاغ عن هذا المحتوى',
    _ => e is ApiException ? e.message : e.toString(),
  };
}

/// يعرض ورقة الإبلاغ ثم يرسل البلاغ (ويحظر [author] إن اختار المستخدم ذلك). يعيد null عند الإلغاء.
/// [type] نوع المحتوى كما في server/safety.js (post, listing, vessel-comment…) أو [kReportUser] للإبلاغ عن شخص.
Future<ReportOutcome?> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  required String id,
  Person? author,
  String title = 'إبلاغ',
  String? messageId,
}) async {
  final myId = ref.read(appStateProvider).user?.id;
  final blocked = ref.read(blockedIdsProvider);
  // خيار الحظر فقط حين نعرف الناشر وليس أنا ولم يُحظر بعد
  final canBlock = myId != null && author != null && author.id.isNotEmpty && author.id.toUpperCase() != myId.toUpperCase() && !blocked.contains(author.id.toUpperCase());
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReportSheet(title: title, blockName: canBlock ? author.nickname : null),
  );
  if (choice == null || !context.mounted) return null;
  final api = ref.read(apiClientProvider);
  var out = const ReportOutcome();
  try {
    if (type == kReportUser) {
      await api.reportUser(id, choice.text, messageId: messageId);
      out = const ReportOutcome(sent: true);
    } else {
      final r = await api.reportContent(type: type, id: id, reason: choice.text);
      out = ReportOutcome(sent: true, hidden: r.hidden);
    }
  } catch (e) {
    final own = e is ApiException && e.body?['error'] == 'own-content';
    if (context.mounted) toast(context, reportErrorText(e), error: true);
    if (own || !choice.block) return out;
  }
  if (choice.block && canBlock) {
    try {
      await api.blockUser(author.id);
      ref.invalidate(blockedUsersProvider);
      out = ReportOutcome(sent: out.sent, hidden: out.hidden, blocked: true);
    } catch (e) {
      if (context.mounted) toast(context, reportErrorText(e), error: true);
      return out;
    }
  }
  if (!context.mounted || !out.sent && !out.blocked) return out;
  final parts = <String>[
    if (out.sent) out.hidden ? 'وصل بلاغك وأُخفي المحتوى للمراجعة' : 'وصل بلاغك وسنراجعه خلال 24 ساعة',
    if (out.blocked) 'وحُظر ${author!.nickname}',
  ];
  toast(context, parts.join(' '));
  return out;
}

/// تأكيد ثم حظر [person]؛ يعيد true إن تم الحظر (ويحدّث قائمة المحظورين فيختفي محتواه من القوائم).
Future<bool> confirmBlock(BuildContext context, WidgetRef ref, Person person) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('حظر ${person.nickname}؟'),
      content: const Text('لن يستطيع مراسلتك، ولن ترى منشوراته وتعليقاته. يمكنك إلغاء الحظر لاحقاً من ماي سبيس.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(key: const Key('block-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حظر')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(apiClientProvider).blockUser(person.id);
    ref.invalidate(blockedUsersProvider);
    if (context.mounted) toast(context, 'تم حظر ${person.nickname}');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, reportErrorText(e), error: true);
    return false;
  }
}

/// زر ⋯ بعنصرين: «إبلاغ» و«حظر الناشر». يُخفى عن محتواي. المفاتيح: `<prefix>-menu` و`<prefix>-report` و`<prefix>-block`.
class ReportMenuButton extends ConsumerWidget {
  final String type, id, keyPrefix;
  final Person? author;
  final String reportLabel;
  final String? sheetTitle;
  final Color? color;
  final double iconSize;
  final void Function(ReportOutcome outcome)? onReported;
  final VoidCallback? onBlocked;
  const ReportMenuButton({
    super.key,
    required this.type,
    required this.id,
    required this.keyPrefix,
    this.author,
    this.reportLabel = 'إبلاغ',
    this.sheetTitle,
    this.color,
    this.iconSize = 20,
    this.onReported,
    this.onBlocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(appStateProvider.select((s) => s.user?.id));
    final a = author;
    final mine = myId != null && a != null && a.id.toUpperCase() == myId.toUpperCase();
    if (mine) return const SizedBox.shrink();
    final canBlock = myId != null && a != null && a.id.isNotEmpty;
    return PopupMenuButton<String>(
      key: Key('$keyPrefix-menu'),
      tooltip: 'خيارات',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded, color: color ?? Joy.textMuted, size: iconSize),
      onSelected: (v) async {
        if (v == 'report') {
          final r = await showReportSheet(context, ref, type: type, id: id, author: a, title: sheetTitle ?? reportLabel);
          if (r != null) {
            onReported?.call(r);
            if (r.blocked) onBlocked?.call();
          }
        } else if (v == 'block' && a != null) {
          if (await confirmBlock(context, ref, a)) onBlocked?.call();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(key: Key('$keyPrefix-report'), value: 'report', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flag_outlined), title: Text(reportLabel))),
        if (canBlock)
          PopupMenuItem(key: Key('$keyPrefix-block'), value: 'block', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${a.nickname}', style: const TextStyle(color: Joy.danger)))),
      ],
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final String title;
  final String? blockName;
  const _ReportSheet({required this.title, this.blockName});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  int? _reason;
  bool _block = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            const Text('اختر السبب؛ تراجع الإدارة البلاغات خلال 24 ساعة ولن يعرف الناشر من أبلغ.', style: TextStyle(color: Joy.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < kReportReasons.length; i++)
                ChoiceChip(key: Key('report-reason-$i'), label: Text(kReportReasons[i]), selected: _reason == i, onSelected: (_) => setState(() => _reason = i)),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('report-note'),
              controller: _note,
              maxLines: 2,
              maxLength: 250,
              decoration: const InputDecoration(hintText: 'تفاصيل إضافية (اختياري)'),
            ),
            if (widget.blockName != null)
              CheckboxListTile(
                key: const Key('report-also-block'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _block,
                onChanged: (v) => setState(() => _block = v ?? false),
                title: Text('حظر ${widget.blockName} أيضاً'),
                subtitle: const Text('لن ترى محتواه ولن يستطيع مراسلتك'),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('report-submit'),
              onPressed: _reason == null ? null : () => Navigator.pop(context, _Choice(kReportReasons[_reason!], _note.text.trim(), _block)),
              child: const Text('إرسال البلاغ'),
            ),
          ]),
        ),
      ),
    );
  }
}
