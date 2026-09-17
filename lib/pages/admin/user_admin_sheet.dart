import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/admin_api.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/admin_providers.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../profile/user_profile_page.dart' show userProfileProvider;
import 'admin_users.dart' show AdminUserPage;

/// نص خطأ مفهوم لإجراءات إدارة الحساب من داخل التطبيق.
String userAdminErrText(Object e) {
  String? code;
  if (e is ApiException && e.body != null) {
    final Object? v = e.body!['error'];
    code = v?.toString();
  }
  switch (code) {
    case 'confirm-mismatch':
      return 'اكتب اسم المستخدم كما هو للتأكيد';
    case 'delete-failed':
      return 'تعذّر الحذف: ${e is ApiException ? (e.body?['detail'] ?? '') : ''}';
    case 'invalid-nickname':
      return 'اسم المستخدم: حروف إنجليزية صغيرة وأرقام و _ فقط (3 إلى 25)';
    case 'nickname-taken':
      return 'اسم المستخدم مستخدم لحساب آخر';
    case 'email-taken':
      return 'هذا البريد مسجّل لحساب آخر';
    case 'no-bio-column':
    case 'no-public-column':
      return 'هذا الحقل غير متاح للتعديل من الإدارة على هذا الخادم';
    case 'self':
      return 'لا يمكنك تطبيق هذا الإجراء على حسابك';
    case 'admin-only':
      return 'هذا الإجراء للمديرين فقط';
    case 'last-admin':
      return 'لا يمكن سحب صلاحية آخر مدير';
  }
  return e is ApiException ? e.message : e.toString();
}

/// ورقة إدارة حساب مستخدم من داخل التطبيق (للمديرين): تعديل الملف، الرصيد، الإيقاف، صلاحية المدير، الحذف النهائي.
Future<void> showUserAdminSheet(BuildContext context, WidgetRef ref, {required String id, required String nickname}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
      builder: (_) => _UserAdminSheet(id: id, nickname: nickname),
    );

class _UserAdminSheet extends ConsumerStatefulWidget {
  final String id, nickname;
  const _UserAdminSheet({required this.id, required this.nickname});
  @override
  ConsumerState<_UserAdminSheet> createState() => _UserAdminSheetState();
}

class _UserAdminSheetState extends ConsumerState<_UserAdminSheet> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(adminUserProvider(widget.id));
    ref.invalidate(userProfileProvider(widget.id));
    ref.invalidate(adminUsersProvider);
    ref.invalidate(contactsProvider);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (mounted && done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, userAdminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(adminUserProvider(widget.id));
    final u = detail.valueOrNull?.user;
    final me = ref.watch(appStateProvider.select((s) => s.user));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.admin_panel_settings_outlined, color: Joy.accent),
          const SizedBox(width: 8),
          const Text('إدارة الحساب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const Spacer(),
          if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(u?.nickname.isNotEmpty == true ? u!.nickname : widget.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(widget.id, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          if (u?.isAdmin == true) _chip('مدير', Joy.primary, Joy.primarySoft),
          if (u?.suspended == true) _chip('موقوف', Joy.danger, Joy.accentSoft),
          if (u?.balance != null) _chip('الرصيد ${money(u!.balance!)}', Joy.success, const Color(0xFFE3F5EA)),
        ]),
        if (u?.suspended == true && u!.flagNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('سبب الإيقاف: ${u.flagNote}', style: const TextStyle(color: Joy.danger, fontSize: 12.5))),
        const SizedBox(height: 8),
        const Divider(),
        ListTile(key: const Key('ua-edit'), leading: const Icon(Icons.edit_outlined, color: Joy.primary), title: const Text('تعديل الملف'), subtitle: const Text('اسم المستخدم، النبذة، الظهور، الصورة'), onTap: _busy ? null : _editProfile),
        ListTile(key: const Key('ua-credit'), leading: const Icon(Icons.account_balance_wallet_outlined, color: Joy.success), title: const Text('إضافة أو خصم رصيد'), onTap: _busy ? null : _credit),
        ListTile(
          key: const Key('ua-suspend'),
          leading: Icon(u?.suspended == true ? Icons.lock_open_rounded : Icons.block_rounded, color: u?.suspended == true ? Joy.success : Joy.warning),
          title: Text(u?.suspended == true ? 'إعادة تفعيل الحساب' : 'إيقاف الحساب'),
          subtitle: Text(u?.suspended == true ? 'يعود إلى الاستخدام الطبيعي' : 'يُمنع من الاستخدام مع ملاحظة تصله'),
          onTap: _busy ? null : _suspend,
        ),
        ListTile(
          key: const Key('ua-admin'),
          leading: Icon(u?.isAdmin == true ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined, color: Joy.primary),
          title: Text(u?.isAdmin == true ? 'سحب صلاحية المدير' : 'منح صلاحية مدير'),
          onTap: _busy || u == null ? null : () => _grant(!u.isAdmin),
        ),
        ListTile(key: const Key('ua-panel'), leading: const Icon(Icons.open_in_new_rounded, color: Joy.textMuted), title: const Text('فتح في لوحة الإدارة'), subtitle: const Text('الحركات والطلبات والبلاغات وسجل الإجراءات'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(id: widget.id)))),
        const Divider(),
        ListTile(
          key: const Key('ua-delete'),
          leading: const Icon(Icons.delete_forever_rounded, color: Joy.danger),
          title: const Text('حذف الحساب نهائياً', style: TextStyle(color: Joy.danger, fontWeight: FontWeight.w700)),
          subtitle: const Text('يُمحى الحساب وكل بياناته من قواعد البيانات ولا يمكن التراجع'),
          onTap: _busy || me?.id == widget.id ? null : _delete,
        ),
      ]),
    );
  }

  Widget _chip(String t, Color fg, Color bg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)));

  Future<void> _editProfile() async {
    final profile = ref.read(userProfileProvider(widget.id)).valueOrNull;
    final nick = TextEditingController(text: profile?.nickname ?? widget.nickname);
    final bio = TextEditingController(text: profile?.bio ?? '');
    var isPublic = profile?.isPublic ?? true, removeAvatar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('تعديل الملف'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(key: const Key('ua-nick'), controller: nick, textDirection: TextDirection.ltr, autocorrect: false, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              const SizedBox(height: 10),
              TextField(key: const Key('ua-bio'), controller: bio, maxLines: 3, decoration: const InputDecoration(labelText: 'النبذة')),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: isPublic, onChanged: (v) => setS(() => isPublic = v), title: const Text('الملف عام')),
              CheckboxListTile(contentPadding: EdgeInsets.zero, value: removeAvatar, onChanged: (v) => setS(() => removeAvatar = v == true), title: const Text('إزالة صورة الحساب')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('ua-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
        ),
      ),
    );
    if (ok != true) return;
    final fields = <String, dynamic>{
      if (nick.text.trim().toLowerCase() != (profile?.nickname ?? widget.nickname)) 'nickname': nick.text.trim().toLowerCase(),
      if (bio.text.trim() != (profile?.bio ?? '')) 'bio': bio.text.trim(),
      if (isPublic != (profile?.isPublic ?? true)) 'isPublic': isPublic,
      if (removeAvatar) 'avatarUrl': null,
    };
    if (fields.isEmpty) return;
    await _run(() => ref.read(apiClientProvider).adminUpdateUser(widget.id, fields), done: 'حُفظت التعديلات');
  }

  Future<void> _credit() async {
    final amount = TextEditingController(), note = TextEditingController();
    var add = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('رصيد المحفظة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('إضافة')), ButtonSegment(value: false, label: Text('خصم'))], selected: {add}, onSelectionChanged: (s) => setS(() => add = s.first)),
            const SizedBox(height: 10),
            TextField(key: const Key('ua-amount'), controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ بالريال')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (تصل للمستخدم)')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنفيذ'))],
        ),
      ),
    );
    if (ok != true) return;
    final h = parseSar(amount.text);
    if (h <= 0) {
      if (mounted) toast(context, 'أدخل مبلغاً صحيحاً', error: true);
      return;
    }
    await _run(() => ref.read(apiClientProvider).adminCredit(widget.id, add ? h : -h, note: note.text.trim()), done: add ? 'أُضيف ${money(h)}' : 'خُصم ${money(h)}');
  }

  Future<void> _suspend() async {
    final u = ref.read(adminUserProvider(widget.id)).valueOrNull?.user;
    final suspended = u?.suspended == true;
    if (suspended) {
      await _run(() => ref.read(apiClientProvider).adminSuspend(widget.id, suspended: false), done: 'أُعيد تفعيل الحساب');
      return;
    }
    final note = await askText(context, title: 'إيقاف ${u?.nickname ?? widget.nickname}', hint: 'سبب الإيقاف (يصل للمستخدم)', confirm: 'إيقاف');
    if (note == null) return;
    await _run(() => ref.read(apiClientProvider).adminSuspend(widget.id, suspended: true, note: note.trim()), done: 'أُوقف الحساب');
  }

  Future<void> _grant(bool grant) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(grant ? 'منح صلاحية مدير؟' : 'سحب صلاحية المدير؟'), content: Text(grant ? 'يصبح قادراً على كل إجراءات لوحة الإدارة.' : 'يفقد الوصول إلى لوحة الإدارة.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد'))]));
    if (ok != true) return;
    await _run(() => ref.read(apiClientProvider).adminGrant(widget.id, grant: grant), done: grant ? 'مُنحت الصلاحية' : 'سُحبت الصلاحية');
  }

  Future<void> _delete() async {
    final u = ref.read(adminUserProvider(widget.id)).valueOrNull?.user;
    final expected = u?.nickname.isNotEmpty == true ? u!.nickname : widget.nickname;
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب نهائياً'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('يُمحى حساب «$expected» وكل ما يخصه: الملف والرسائل والمنشورات والمحفظة وبريد الدخول، من كل جداول قاعدة البيانات. لا يمكن التراجع.', style: const TextStyle(height: 1.6)),
          const SizedBox(height: 10),
          TextField(key: const Key('ua-confirm'), controller: typed, textDirection: TextDirection.ltr, autocorrect: false, decoration: InputDecoration(labelText: 'اكتب $expected للتأكيد')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(key: const Key('ua-delete-go'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف نهائي')),
        ],
      ),
    );
    if (ok != true) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final report = await ref.read(apiClientProvider).adminDeleteUser(widget.id, confirm: typed.text.trim());
      final rows = report.values.fold<int>(0, (n, v) => n + (v is num ? v.toInt() : 0));
      ref.invalidate(adminUsersProvider);
      ref.invalidate(contactsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(); // الورقة
      Navigator.of(context).popUntil((r) => r.isFirst); // صفحة الملف المحذوف
      toast(context, 'حُذف حساب «$expected» نهائياً ($rows صفاً)');
    } catch (e) {
      if (mounted) toast(context, userAdminErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
