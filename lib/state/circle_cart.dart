// سلة الدائرة على الجهاز (نوفمبر 2026): سلة لكل حساب ودائرة تُحفظ في SharedPreferences (naslife.cart.<uid>.<bizId>) فتبقى بعد إغلاق
// التطبيق، ولا يراها حساب آخر يدخل على الجهاز نفسه.
// السطر يحفظ الصنف وكميته وخياراته فقط؛ السعر يُعاد حسابه من الكتالوج الحالي عند العرض، والخادم يحسب المبلغ النهائي عند الطلب.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/biz_models.dart';
import 'app_state.dart';

/// سطر في السلة: الصنف والكمية والخيارات المختارة (معرّف المجموعة ← معرّفات الخيارات).
class CartLine {
  final String itemId;
  final int qty;
  final Map<String, List<String>> options;
  const CartLine({required this.itemId, this.qty = 1, this.options = const {}});

  /// الصنف نفسه بالخيارات نفسها سطر واحد تزيد كميته؛ بخيارات مختلفة سطر جديد.
  String get key {
    final groups = options.keys.where((g) => options[g]!.isNotEmpty).toList()..sort();
    return '$itemId|${groups.map((g) => '$g=${([...options[g]!]..sort()).join(',')}').join(';')}';
  }

  CartLine withQty(int q) => CartLine(itemId: itemId, qty: q, options: options);
  Map<String, dynamic> toJson() => {'itemId': itemId, 'qty': qty, 'options': {for (final e in options.entries) if (e.value.isNotEmpty) e.key: e.value}};
  factory CartLine.fromJson(Map m) => CartLine(
        itemId: m['itemId']?.toString() ?? '',
        qty: (m['qty'] is num ? (m['qty'] as num).toInt() : int.tryParse('${m['qty']}') ?? 1).clamp(1, maxCartQty),
        options: {
          if (m['options'] is Map)
            for (final e in (m['options'] as Map).entries)
              if (e.value is List) e.key.toString(): [for (final v in e.value as List) v.toString()],
        },
      );
}

/// حدود الخادم نفسها: 20 قطعة للسطر، و20 سطراً، و50 قطعة في السلة.
const maxCartQty = 20, maxCartLines = 20, maxCartPieces = 50;

/// مفتاح سلة الحساب في الدائرة؛ الزائر لا يضيف إلى السلة (الإضافة تطلب الدخول) فمفتاحه احتياط فقط.
String cartStorageKey(String? uid, String bizId) => 'naslife.cart.${uid ?? 'guest'}.$bizId';

/// يمسح سلال حساب من الجهاز (عند حذف الحساب: لا تبقى أسطره في تخزين جهاز قد يستعمله غيره).
Future<void> forgetSavedCarts(String uid) async {
  try {
    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys().where((k) => k.startsWith('naslife.cart.$uid.')).toList()) {
      await sp.remove(k);
    }
  } catch (_) {
    // التخزين غير متاح: لا شيء محفوظ أصلاً
  }
}

class CircleCart extends StateNotifier<List<CartLine>> {
  final String bizId;
  final String? uid;
  late final Future<void> _loaded = _load();
  CircleCart(this.bizId, {this.uid}) : super(const []) {
    _loaded.ignore();
  }

  String get _key => cartStorageKey(uid, bizId);

  /// يقرأ المحفوظ ويدمج معه ما أُضيف قبل اكتمال القراءة (لا تمحو الإضافة الأولى سلة الجلسة السابقة).
  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      // المفتاح القديم بلا حساب (naslife.cart.<bizId>) لا يُعرف صاحبه فلا يُقرأ لأحد ويُحذف
      if (sp.containsKey('naslife.cart.$bizId')) await sp.remove('naslife.cart.$bizId');
      final raw = sp.getString(_key);
      final list = raw == null || raw.isEmpty ? const [] : jsonDecode(raw);
      if (list is! List || !mounted) return;
      final restored = [for (final e in list) if (e is Map) CartLine.fromJson(e)].where((l) => l.itemId.isNotEmpty).toList();
      if (restored.isEmpty) return;
      final merged = <String, CartLine>{for (final l in restored) l.key: l};
      for (final l in state) {
        final had = merged[l.key];
        merged[l.key] = had == null ? l : had.withQty((had.qty + l.qty).clamp(1, maxCartQty));
      }
      state = merged.values.take(maxCartLines).toList();
    } catch (_) {
      // التخزين غير متاح (وضع خاص أو اختبار): السلة تعمل في الذاكرة
    }
  }

  Future<void> _save() async {
    // الأسطر تُلتقط قبل الانتظار: تبديل الحساب يتلف هذه السلة وقد يأتي الحفظ بعده
    final lines = state;
    await _loaded;
    try {
      final sp = await SharedPreferences.getInstance();
      if (lines.isEmpty) {
        await sp.remove(_key);
      } else {
        await sp.setString(_key, jsonEncode([for (final l in lines) l.toJson()]));
      }
    } catch (_) {
      // كما في القراءة
    }
  }

  int get pieces => state.fold(0, (n, l) => n + l.qty);

  /// يضيف السطر (أو يزيد كمية السطر المطابق)؛ يعيد false إن تجاوز حدود السلة.
  bool add(CartLine line) {
    final i = state.indexWhere((l) => l.key == line.key);
    if (pieces + line.qty > maxCartPieces) return false;
    if (i >= 0) {
      final q = state[i].qty + line.qty;
      if (q > maxCartQty) return false;
      state = [for (final (j, l) in state.indexed) j == i ? l.withQty(q) : l];
    } else {
      if (state.length >= maxCartLines) return false;
      state = [...state, line];
    }
    _save();
    return true;
  }

  void setQty(String key, int qty) {
    state = qty <= 0 ? [for (final l in state) if (l.key != key) l] : [for (final l in state) l.key == key ? l.withQty(qty.clamp(1, maxCartQty)) : l];
    _save();
  }

  void remove(String key) => setQty(key, 0);

  void clear() {
    state = const [];
    _save();
  }
}

/// السلة تتبع الحساب الداخل: الخروج أو تبديل الحساب على الجهاز نفسه يعيد بناءها من سلة الحساب الجديد (لا يرى أحد سلة من قبله).
final circleCartProvider = StateNotifierProvider.family<CircleCart, List<CartLine>, String>((ref, bizId) {
  final uid = ref.watch(appStateProvider.select((s) => s.session?.user.id));
  return CircleCart(bizId, uid: uid);
});

/// سطر السلة كما يُعرض الآن: الصنف من الكتالوج الحالي، وسعر الوحدة التقديري، وهل ما زال متاحاً للطلب.
class ResolvedCartLine {
  final CartLine line;
  final BizItem? item;
  /// سعر الوحدة التقديري: السعر الخاص للوحدة إن انطبق ثم فروق الخيارات كاملة، كما يحسبه الخادم للسطر
  /// (المبلغ النهائي بالكوبونات من معاينة الخادم في ورقة الإتمام).
  final int unit;
  /// null = متاح؛ وإلا سبب عدم الإتاحة للعرض.
  final String? problem;
  const ResolvedCartLine({required this.line, this.item, this.unit = 0, this.problem});
  int get total => unit * line.qty;
  bool get ok => problem == null;
  /// السطر مجاني بسعر الصنف وفروقه (قبل أي عرض)، كما يعدّه الخادم.
  bool get free => item != null && item!.price + item!.optionsDelta(line.options) == 0;
  /// يقبل الدفع في المكان: الصنف يقبله، أو السطر مجاني فلا يُدفع له شيء (كقاعدة الخادم).
  bool get venueOk => item != null && (free || item!.payAtVenue);
  String get title => item?.title ?? 'صنف محذوف';
  String get optionsLabel => item?.optionsLabel(line.options) ?? '';
}

/// يطابق أسطر السلة بكتالوج الدائرة الحالي.
List<ResolvedCartLine> resolveCart(Biz biz, List<CartLine> lines) {
  final need = <String, int>{};
  for (final l in lines) {
    need[l.itemId] = (need[l.itemId] ?? 0) + l.qty;
  }
  return [
    for (final l in lines)
      () {
        final it = biz.items.where((i) => i.id == l.itemId).firstOrNull;
        if (it == null || !it.active || it.kind != 'product') return ResolvedCartLine(line: l, problem: 'لم يعد متاحاً');
        // سعر الأعضاء الخاص يُحسب لمن انضم فقط، كما يطبّقه الخادم
        final deal = it.deal != null && (!it.deal!.membersOnly || biz.following) ? it.deal : null;
        final unit = (deal?.price ?? it.price) + it.optionsDelta(l.options);
        if (!it.selectionValid(l.options)) return ResolvedCartLine(line: l, item: it, unit: unit, problem: 'تغيّرت خيارات هذا الصنف، احذفه وأضفه من جديد');
        if (it.soldOut) return ResolvedCartLine(line: l, item: it, unit: unit, problem: 'نفدت الكمية');
        if (it.stock != null && need[l.itemId]! > it.stock!) return ResolvedCartLine(line: l, item: it, unit: unit, problem: 'المتبقي ${it.stock} فقط');
        return ResolvedCartLine(line: l, item: it, unit: unit);
      }(),
  ];
}
