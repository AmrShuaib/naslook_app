/// رموز الاختصار في المحادثة: `@` للأشخاص والدوائر، `#` للأصناف والفعاليات والعروض والمنشورات، و`/` للأفعال.
/// المحلّل هنا لا يعرف الأسماء والأسعار (الخادم يجلبها عند العرض)، بل يميّز الرمز عن النص العادي ويستخرج حججه.
/// الرمز غير الصحيح يبقى نصاً عادياً ولا يعطّل الرسالة.
library;

/// أنواع الرموز.
enum CodeKind {
  // إشارات (تُحلّ عبر GET /chat/cards)
  mention, item, event, listing, post, space, spacePost, ticket, order,
  // أفعال (تُسجَّل عبر POST /chat/requests أو تُعرض كما هي)
  pay, send, split, meet, invite, where, loc, me,
}

extension CodeKindX on CodeKind {
  bool get isRef => index <= CodeKind.order.index;
  /// أفعال تُسجَّل في الخادم بمعرّف الرسالة (حالة: معلّق/مدفوع/مقبول…)
  bool get needsRequest => this == CodeKind.pay || this == CodeKind.send || this == CodeKind.split || this == CodeKind.meet;
}

/// رمز واحد داخل نص رسالة.
class ChatCode {
  final CodeKind kind;
  /// النص كما كُتب (`#brew92/v60` أو `/pay 45 قهوة`).
  final String raw;
  /// مفتاح الحلّ عند الخادم للإشارات (`@sara`، `#ev/…`)، وللدعوة/الموعد مرجع الدائرة أو الفعالية إن وُجد.
  final String? ref;
  /// المبلغ بالهللات (pay/send/split).
  final int amount;
  /// عدد الأشخاص في التقسيم.
  final int n;
  /// سبب المبلغ أو وقت الموعد.
  final String note;
  /// مكان الموعد (نص حر أو `@دائرة`).
  final String place;
  final double? lat, lng;
  /// موضع الرمز في النص.
  final int start, end;
  const ChatCode(this.kind, this.raw, {this.ref, this.amount = 0, this.n = 1, this.note = '', this.place = '', this.lat, this.lng, this.start = 0, this.end = 0});

  /// نصيب الشخص الواحد في التقسيم (تقريب لأعلى).
  int get share => kind == CodeKind.split ? (amount / n).ceil() : amount;
  @override
  String toString() => 'ChatCode(${kind.name} $raw)';
}

/// نتيجة تحليل نص رسالة.
class ParsedText {
  final String text;
  /// أمر في بداية الرسالة إن وُجد.
  final ChatCode? command;
  /// الإشارات داخل النص (بحد أقصى [maxRefs]).
  final List<ChatCode> refs;
  const ParsedText(this.text, {this.command, this.refs = const []});
  bool get hasCodes => command != null || refs.isNotEmpty;
  /// الرسالة أمر فقط بلا نص آخر: تُعرض البطاقة وحدها.
  bool get commandOnly => command != null && command!.end >= text.trimRight().length;
  List<ChatCode> get all => [if (command != null) command!, ...refs];
  /// مفاتيح الحلّ المطلوبة من الخادم.
  Iterable<String> get refKeys => all.map((c) => c.ref).whereType<String>();
}

const maxRefs = 4;
const codeCommands = ['pay', 'send', 'split', 'meet', 'invite', 'where', 'loc', 'me', 'ticket', 'order', 'wish', 'help'];

final _slug = RegExp(r'^[a-z0-9][a-z0-9-]{1,63}$');
final _uuid = RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false);
final _code = RegExp(r'^[A-Z0-9][A-Z0-9-]{4,40}$', caseSensitive: false);
final _nick = RegExp(r'^[\p{L}\p{N}_.\-]{2,40}$', unicode: true);
// إشارة: @ أو # غير مسبوقة بحرف لاتيني أو رقم أو رمز (فلا تُلتقط عناوين البريد ولا أجزاء الروابط)، ويجوز أن يسبقها حرف عربي
// ملتصق مثل واو العطف («و#brew92/v60»)، متبوعة بحروف وأرقام وشرطات ونقاط وشرطة مائلة
final _refRe = RegExp(r'(?<![A-Za-z0-9@#/._\-])([@#][\p{L}\p{N}_.\-/]+)', unicode: true);
final _trailingPunct = RegExp(r'[.،,!?:;)\]»"\x27]+$');
// أرقام عربية وفارسية → لاتينية
String _digits(String s) {
  const east = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = east.indexOf(ch), j = persian.indexOf(ch);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch);
  }
  return b.toString();
}

/// مبلغ بالريال (نص) → هللات، أو null إن لم يُفهم أو كان صفراً.
int? parseAmount(String s) {
  final v = double.tryParse(_digits(s).replaceAll('٫', '.').replaceAll(',', ''));
  if (v == null || v <= 0 || v > 1000000) return null;
  return (v * 100).round();
}

/// يحلّل إشارة واحدة (`@sara`، `#brew92/v60`، `#ev/…`)؛ null إن لم تكن رمزاً صحيحاً.
ChatCode? parseRef(String token, {int start = 0}) {
  var t = token.replaceAll(_trailingPunct, '');
  if (t.length < 2) return null;
  final end = start + t.length;
  if (t[0] == '@') {
    final x = t.substring(1);
    if (x.contains('/') || !_nick.hasMatch(x)) return null;
    return ChatCode(CodeKind.mention, t, ref: t, start: start, end: end);
  }
  final parts = t.substring(1).split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2 || parts.length > 3) return null;
  final a = parts[0], b = parts[1], c = parts.length > 2 ? parts[2] : null;
  switch (a) {
    case 'ev':
      return c == null && _uuid.hasMatch(b) ? ChatCode(CodeKind.event, t, ref: t, start: start, end: end) : null;
    case 'mk':
      return c == null && _uuid.hasMatch(b) ? ChatCode(CodeKind.listing, t, ref: t, start: start, end: end) : null;
    case 'post':
      return c == null && _uuid.hasMatch(b) ? ChatCode(CodeKind.post, t, ref: t, start: start, end: end) : null;
    case 'space':
      if (!_slug.hasMatch(b)) return null;
      if (c == null) return ChatCode(CodeKind.space, t, ref: t, start: start, end: end);
      return _uuid.hasMatch(c) ? ChatCode(CodeKind.spacePost, t, ref: t, start: start, end: end) : null;
    case 't':
      return c == null && _code.hasMatch(b) ? ChatCode(CodeKind.ticket, t, ref: t, start: start, end: end) : null;
    case 'o':
      return c == null && _code.hasMatch(b) ? ChatCode(CodeKind.order, t, ref: t, start: start, end: end) : null;
    default:
      return c == null && _slug.hasMatch(a) && _slug.hasMatch(b) ? ChatCode(CodeKind.item, t, ref: t, start: start, end: end) : null;
  }
}

/// يحلّل أمراً في بداية النص (`/pay 45 قهوة`)؛ null إن لم يكن أمراً مفهوماً بحجج صحيحة.
/// الأوامر `/me` و`/loc` (بلا إحداثيات) و`/ticket` و`/order` و`/wish` و`/help` يوسّعها المؤلّف قبل الإرسال، فلا تُعدّ رموزاً هنا.
ChatCode? parseCommand(String text) {
  final t = text.trimLeft();
  if (!t.startsWith('/')) return null;
  final offset = text.length - t.length;
  final line = t.split('\n').first;
  final m = RegExp(r'^/([a-zA-Z]+)(?:\s+(.*))?$').firstMatch(line.trimRight());
  if (m == null) return null;
  final cmd = m.group(1)!.toLowerCase();
  final args = (m.group(2) ?? '').trim();
  final end = offset + line.trimRight().length;
  final words = args.isEmpty ? const <String>[] : args.split(RegExp(r'\s+'));
  switch (cmd) {
    case 'pay':
    case 'send':
      if (words.isEmpty) return null;
      final amount = parseAmount(words.first);
      if (amount == null) return null;
      return ChatCode(cmd == 'pay' ? CodeKind.pay : CodeKind.send, line.trimRight(), amount: amount, note: words.skip(1).join(' '), start: offset, end: end);
    case 'split':
      if (words.length < 2) return null;
      final amount = parseAmount(words[0]);
      final n = int.tryParse(_digits(words[1]));
      if (amount == null || n == null || n < 2 || n > 20) return null;
      return ChatCode(CodeKind.split, line.trimRight(), amount: amount, n: n, note: words.skip(2).join(' '), start: offset, end: end);
    case 'meet':
      if (words.isEmpty) return null;
      final place = words.skip(1).join(' ');
      final placeRef = place.startsWith('@') ? parseRef(place.split(' ').first)?.ref : null;
      return ChatCode(CodeKind.meet, line.trimRight(), note: words.first, place: place, ref: placeRef, start: offset, end: end);
    case 'invite':
      if (words.isEmpty) return null;
      var target = words.first;
      if (target.startsWith('ev/')) target = '#$target';
      if (!target.startsWith('@') && !target.startsWith('#')) target = '@$target';
      final ref = parseRef(target);
      if (ref == null || (ref.kind != CodeKind.mention && ref.kind != CodeKind.event)) return null;
      return ChatCode(CodeKind.invite, line.trimRight(), ref: ref.ref, note: words.skip(1).join(' '), start: offset, end: end);
    case 'where':
      return ChatCode(CodeKind.where, line.trimRight(), note: args, start: offset, end: end);
    case 'loc':
      if (words.isEmpty) return null;
      final p = _digits(words.first).split(',');
      if (p.length != 2) return null;
      final lat = double.tryParse(p[0]), lng = double.tryParse(p[1]);
      if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
      return ChatCode(CodeKind.loc, line.trimRight(), lat: lat, lng: lng, note: words.skip(1).join(' '), start: offset, end: end);
    default:
      return null;
  }
}

/// يحلّل نص رسالة كاملاً: أمر في البداية (إن وُجد) وإشارات في أي موضع.
ParsedText parseChatText(String text) {
  final command = parseCommand(text);
  final refs = <ChatCode>[];
  final from = command?.end ?? 0;
  final seen = <String>{};
  for (final m in _refRe.allMatches(text, from)) {
    final c = parseRef(m.group(1)!, start: m.start);
    if (c == null || !seen.add(c.raw)) continue;
    refs.add(c);
    if (refs.length >= maxRefs) break;
  }
  return ParsedText(text, command: command, refs: refs);
}

/// معرّف الدائرة القصير كما يُكتب في الرموز (`biz-brew92` → `brew92`).
String shortBiz(String bizId) => bizId.startsWith('biz-') ? bizId.substring(4) : bizId;

/// رمز صنف: `#brew92/v60` (يحذف بادئة الدائرة من معرّف الصنف إن وُجدت).
String itemCode(String bizId, String itemId) {
  final b = shortBiz(bizId);
  final i = itemId.startsWith('$b-') ? itemId.substring(b.length + 1) : itemId.startsWith('$bizId-') ? itemId.substring(bizId.length + 1) : itemId;
  return '#$b/$i';
}

String circleCode(String bizId) => '@${shortBiz(bizId)}';
String userCode(String nickname) => '@$nickname';
String eventCode(String id) => '#ev/$id';
String listingCode(String id) => '#mk/$id';
String postCode(String id) => '#post/$id';
String spaceCode(String bizId, [String? postId]) => postId == null ? '#space/${shortBiz(bizId)}' : '#space/${shortBiz(bizId)}/$postId';
String ticketCode(String code) => '#t/$code';
String orderCode(String code) => '#o/$code';

/// بند في كتالوج الرموز (للإكمال التلقائي وقائمة «+» والدليل).
class CodeEntry {
  final String trigger;
  final String label;
  final String hint;
  final String example;
  final String description;
  const CodeEntry(this.trigger, this.label, this.hint, this.example, this.description);
}

/// الأفعال المتاحة بالترتيب الذي يظهر في الإكمال التلقائي.
const commandCatalog = [
  CodeEntry('/pay', 'طلب مبلغ', '/pay المبلغ [السبب]', '/pay 45 قهوة أمس', 'يطلب من الطرف الآخر مبلغاً يدفعه بزر واحد من محفظته. ينتهي بعد يوم.'),
  CodeEntry('/send', 'إرسال مبلغ', '/send المبلغ [السبب]', '/send 100 هدية', 'يحوّل المبلغ من محفظتك فوراً بعد تأكيدك، ويظهر للطرف الآخر إشعار الاستلام.'),
  CodeEntry('/split', 'تقسيم فاتورة', '/split المبلغ العدد', '/split 180 4', 'يقسم الفاتورة بالتساوي ويعرض نصيب كل شخص، والطرف الآخر يدفع نصيبه فقط.'),
  CodeEntry('/meet', 'اقتراح موعد', '/meet الوقت [المكان]', '/meet 7م @brew92', 'يقترح وقتاً ومكاناً (دائرة أو نص)، والطرف الآخر يوافق أو يقترح غيره.'),
  CodeEntry('/loc', 'موقعي الآن', '/loc', '/loc', 'يرسل موقعك الحالي نقطة على الخريطة مع زر اتجاهات.'),
  CodeEntry('/where', 'أين أنت؟', '/where', '/where', 'يطلب من الطرف الآخر مشاركة موقعه بزر واحد.'),
  CodeEntry('/invite', 'دعوة', '/invite الدائرة أو ev/الفعالية', '/invite brew92', 'يدعو الطرف الآخر للانضمام إلى دائرة أو حضور فعالية.'),
  CodeEntry('/ticket', 'تذكرتي', '/ticket ثم اختر', '/ticket', 'يعرض تذاكرك لتختار واحدة تشاركها ببطاقة فيها الفعالية والرمز.'),
  CodeEntry('/order', 'حجزي أو طلبي', '/order ثم اختر', '/order', 'يعرض حجوزاتك وطلباتك من الدوائر لتشارك واحداً برمزه.'),
  CodeEntry('/wish', 'من أمنياتي', '/wish ثم اختر', '/wish', 'يعرض قائمة أمنياتك لتشارك واحدة منها كبطاقة.'),
  CodeEntry('/me', 'ملفي', '/me', '/me', 'يرسل بطاقة حسابك: صورتك واسمك ورابطك.'),
  CodeEntry('/help', 'دليل الرموز', '/help', '/help', 'يفتح دليل الرموز مع أمثلة.'),
];

/// أوامر المال (طلب مبلغ، إرسال، تقسيم): تُحذف من الكتالوج والإكمال والدليل في iOS أو حين يطفئها المدير.
const moneyCommands = {'/pay', '/send', '/split'};

/// هل النص يبدأ بأمر مال؟ (/pay، /send، /split، مع أي حجج بعده)
bool isMoneyCommand(String text) {
  final m = RegExp(r'^(/[a-zA-Z]+)(?:\s|$)').firstMatch(text.trimLeft());
  return m != null && moneyCommands.contains(m.group(1)!.toLowerCase());
}

/// الأفعال المتاحة: الكتالوج كاملاً، أو بلا أوامر المال حين تكون غير متاحة.
List<CodeEntry> commandsFor({required bool money}) => money ? commandCatalog : [for (final c in commandCatalog) if (!moneyCommands.contains(c.trigger)) c];

/// أشكال الإشارات (للدليل والإكمال).
const refCatalog = [
  CodeEntry('@', 'شخص', '@النك نيم', '@sara', 'بطاقة الحساب: الصورة والاسم وزر مراسلة.'),
  CodeEntry('@', 'دائرة', '@معرّف الدائرة', '@brew92', 'بطاقة الدائرة: الشعار والاسم والحي ومفتوح أم مغلق.'),
  CodeEntry('#', 'صنف من دائرة', '#الدائرة/الصنف', '#brew92/v60', 'بطاقة الصنف: الاسم والسعر وعدد النقاشات وزر اطلب.'),
  CodeEntry('#ev/', 'فعالية', '#ev/معرّف', '#ev/2a7c…', 'بطاقة الفعالية: العنوان والتاريخ والسعر والمقاعد.'),
  CodeEntry('#mk/', 'عرض في السوق', '#mk/معرّف', '#mk/9b1d…', 'بطاقة العرض: الصورة والسعر والبائع.'),
  CodeEntry('#post/', 'منشور على الخريطة', '#post/معرّف', '#post/8a1c…', 'بطاقة المنشور: الصورة مصغّرة وصاحبه ومكانه.'),
  CodeEntry('#space/', 'مساحة نقاش', '#space/الدائرة[/المشاركة]', '#space/brew92', 'بطاقة المساحة أو مشاركة بعينها مع كاتبها.'),
  CodeEntry('#t/', 'تذكرة', '#t/الرمز', '#t/NAS-A1B2C3D4', 'بطاقة التذكرة: الفعالية والفئة والرمز (تُدرج عبر /ticket).'),
  CodeEntry('#o/', 'حجز أو طلب', '#o/الرمز', '#o/NAS-E5F6A7B8', 'بطاقة الحجز: الصنف والدائرة والحالة (تُدرج عبر /order).'),
];
