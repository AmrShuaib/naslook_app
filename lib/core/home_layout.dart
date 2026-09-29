import 'package:flutter/material.dart';

/// تخصيص الرئيسية: كل مستخدم يخفي أقسام الشاشة الرئيسية ويرتّبها ويختار أقسام شريط التنقّل.
/// المعرّفات والترتيب الافتراضي مطابقان لما في `server/layout.js`.

/// وصف قسم من أقسام الرئيسية (للمحرّر والقائمة).
class HomeBlockMeta {
  final String id, title, hint;
  final IconData icon;
  const HomeBlockMeta(this.id, this.title, this.icon, this.hint);
}

const homeBlocks = <HomeBlockMeta>[
  HomeBlockMeta('announce', 'إعلان المنصة', Icons.campaign_outlined, 'يظهر فقط عند وجود إعلان'),
  HomeBlockMeta('quick', 'الاختصارات', Icons.grid_view_rounded, 'الدوائر والسوق والفعاليات والمحفظة…'),
  HomeBlockMeta('around', 'لحظات حولك', Icons.auto_awesome_rounded, 'لحظات الأشخاص القريبين وبث المدينة'),
  HomeBlockMeta('trending', 'الأماكن الرائجة اليوم', Icons.local_fire_department_outlined, 'الأكثر لحظات خلال ٢٤ ساعة'),
  HomeBlockMeta('open', 'مفتوح الآن حولك', Icons.schedule_rounded, 'أنشطة مفتوحة الآن مرتبة بالأقرب'),
  HomeBlockMeta('circles', 'دوائرك', Icons.groups_outlined, 'الدوائر التي أنت عضو فيها'),
  HomeBlockMeta('feed', 'آخر ما في دوائرك', Icons.forum_outlined, 'منشورات دوائرك الأحدث'),
  HomeBlockMeta('biz', 'الدوائر التجارية', Icons.local_mall_outlined, 'براندات وسينما وفنادق ومستشفيات ومقاهٍ'),
  HomeBlockMeta('jobs', 'وظائف جديدة', Icons.work_outline_rounded, 'آخر الوظائف المنشورة في الدوائر'),
  HomeBlockMeta('market', 'من السوق', Icons.shopping_bag_outlined, 'إعلانات قريبة ورائجة'),
  HomeBlockMeta('events', 'فعاليات قريبة', Icons.event_outlined, 'فعاليات وبازارات قادمة'),
];

const homeDefaultOrder = ['announce', 'quick', 'around', 'trending', 'open', 'circles', 'feed', 'jobs', 'market', 'events', 'biz'];
const homeDefaultPinned = ['announce'];

/// قسم من شريط التنقّل السفلي.
class NavTabMeta {
  final String id, label;
  final IconData icon, selectedIcon;
  final bool locked;
  const NavTabMeta(this.id, this.label, this.icon, this.selectedIcon, {this.locked = false});
}

/// «الخريطة» أولاً و«ماي سبيس» آخراً ثابتان؛ بينهما قسمان يختارهما المستخدم (زر الكاميرا في الوسط).
const navTabs = <NavTabMeta>[
  NavTabMeta('home', 'الخريطة', Icons.map_outlined, Icons.map_rounded, locked: true),
  NavTabMeta('circles', 'الدوائر', Icons.groups_outlined, Icons.groups_rounded),
  NavTabMeta('chats', 'المحادثات', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  NavTabMeta('market', 'السوق', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
  NavTabMeta('offers', 'العروض', Icons.local_offer_outlined, Icons.local_offer_rounded),
  NavTabMeta('jobs', 'الوظائف', Icons.work_outline_rounded, Icons.work_rounded),
  NavTabMeta('events', 'الفعاليات', Icons.event_outlined, Icons.event_rounded),
  NavTabMeta('me', 'ماي سبيس', Icons.person_outline_rounded, Icons.person_rounded, locked: true),
];
const navDefault = ['home', 'circles', 'chats', 'me'];
/// عدد الأقسام المتاحة بين الطرفين الثابتين.
const navMiddleSlots = 2;

HomeBlockMeta? homeBlockMeta(String id) {
  for (final b in homeBlocks) {
    if (b.id == id) return b;
  }
  return null;
}

NavTabMeta? navTabMeta(String id) {
  for (final t in navTabs) {
    if (t.id == id) return t;
  }
  return null;
}

/// حالة التخصيص: الترتيب، المخفي، أقسام الشريط، وخيارات كل قسم. غير قابلة للتغيير؛ كل تعديل يعيد نسخة.
class HomeLayout {
  final List<String> order;
  final List<String> hidden;
  final List<String> nav;
  final Map<String, List<String>> opts;
  /// أقسام مثبّتة لا تُخفى (من إعدادات الإدارة).
  final List<String> pinned;
  /// أقسام ظهرت بعد آخر حفظ للمستخدم (توسم «جديد» حتى يلمسها).
  final List<String> fresh;

  const HomeLayout({this.order = homeDefaultOrder, this.hidden = const [], this.nav = navDefault, this.opts = const {}, this.pinned = homeDefaultPinned, this.fresh = const []});

  static const defaults = HomeLayout();

  /// يبني حالة صالحة من أي مدخل: يحذف المجهول والمكرر، يضيف الأقسام الناقصة آخر القائمة، ويثبّت طرفي الشريط.
  factory HomeLayout.normalized({Iterable<String>? order, Iterable<String>? hidden, Iterable<String>? nav, Map<String, List<String>>? opts, Iterable<String>? pinned, Iterable<String>? fresh, List<String> defaultOrder = homeDefaultOrder}) {
    final known = {for (final b in homeBlocks) b.id};
    final pin = [for (final p in (pinned ?? homeDefaultPinned)) if (known.contains(p)) p];
    final seen = <String>{};
    final o = <String>[];
    for (final id in [...pin, ...(order ?? defaultOrder), ...defaultOrder]) {
      if (known.contains(id) && seen.add(id)) o.add(id);
    }
    final h = <String>{for (final id in (hidden ?? const <String>[])) if (known.contains(id) && !pin.contains(id)) id}.toList();
    final navKnown = {for (final t in navTabs) t.id};
    final mid = <String>[];
    for (final id in (nav ?? navDefault)) {
      if (id != 'home' && id != 'me' && navKnown.contains(id) && !mid.contains(id) && mid.length < navMiddleSlots) mid.add(id);
    }
    final f = [for (final id in (fresh ?? const <String>[])) if (known.contains(id)) id];
    return HomeLayout(order: o, hidden: h, nav: ['home', ...mid, 'me'], opts: {for (final e in (opts ?? const {}).entries) if (known.contains(e.key)) e.key: List<String>.unmodifiable(e.value)}, pinned: pin, fresh: f);
  }

  factory HomeLayout.fromJson(Map m, {Iterable<String>? pinned, List<String> defaultOrder = homeDefaultOrder}) => HomeLayout.normalized(
        order: (m['order'] as List?)?.map((e) => e.toString()),
        hidden: (m['hidden'] as List?)?.map((e) => e.toString()),
        nav: (m['nav'] as List?)?.map((e) => e.toString()),
        opts: {for (final e in ((m['opts'] as Map?) ?? const {}).entries) e.key.toString(): [for (final v in (e.value as List? ?? const [])) v.toString()]},
        pinned: pinned ?? (m['pinned'] as List?)?.map((e) => e.toString()),
        fresh: (m['fresh'] as List?)?.map((e) => e.toString()),
        defaultOrder: defaultOrder,
      );

  Map<String, dynamic> toJson() => {'order': order, 'hidden': hidden, 'nav': nav, 'opts': opts, 'pinned': pinned, 'fresh': fresh};

  /// الأقسام الظاهرة بترتيبها.
  List<String> get visible => [for (final id in order) if (!hidden.contains(id)) id];
  bool isHidden(String id) => hidden.contains(id);
  bool isPinned(String id) => pinned.contains(id);
  bool isFresh(String id) => fresh.contains(id);
  bool get isDefault => hidden.isEmpty && _same(order, HomeLayout.normalized(pinned: pinned).order) && _same(nav, navDefault) && opts.values.every((v) => v.isEmpty);

  HomeLayout copyWith({List<String>? order, List<String>? hidden, List<String>? nav, Map<String, List<String>>? opts, List<String>? pinned, List<String>? fresh}) =>
      HomeLayout.normalized(order: order ?? this.order, hidden: hidden ?? this.hidden, nav: nav ?? this.nav, opts: opts ?? this.opts, pinned: pinned ?? this.pinned, fresh: fresh ?? this.fresh);

  HomeLayout hide(String id) => isPinned(id) ? this : copyWith(hidden: [...hidden, id], fresh: [for (final f in fresh) if (f != id) f]);
  HomeLayout show(String id) => copyWith(hidden: [for (final h in hidden) if (h != id) h], fresh: [for (final f in fresh) if (f != id) f]);
  HomeLayout toggle(String id) => isHidden(id) ? show(id) : hide(id);

  /// ينقل القسم خطوة بين الأقسام الظاهرة (dir = -1 لأعلى، +1 لأسفل) دون تخطي المثبّت.
  HomeLayout move(String id, int dir) {
    if (isPinned(id)) return this;
    final vis = visible;
    final vi = vis.indexOf(id);
    final j = vi + dir;
    if (vi < 0 || j < 0 || j >= vis.length || isPinned(vis[j])) return this;
    final o = [...order];
    final i = o.indexOf(id);
    final oi = o.indexOf(vis[j]);
    o.removeAt(i);
    o.insert(oi, id);
    return copyWith(order: o);
  }

  /// يضع القسم أول الأقسام غير المثبّتة.
  HomeLayout toTop(String id) {
    if (isPinned(id)) return this;
    final o = [for (final x in order) if (x != id) x];
    o.insert(pinned.where(o.contains).length, id);
    return copyWith(order: o);
  }

  /// إعادة ترتيب كاملة (من محرّر السحب): القائمة تحوي الأقسام كلها بترتيبها الجديد.
  HomeLayout reorder(List<String> newOrder) => copyWith(order: newOrder);

  HomeLayout withNav(List<String> middle) => copyWith(nav: ['home', ...middle, 'me']);
  HomeLayout toggleOpt(String id, String opt) {
    final cur = opts[id] ?? const <String>[];
    return copyWith(opts: {...opts, id: cur.contains(opt) ? [for (final o in cur) if (o != opt) o] : [...cur, opt]});
  }

  HomeLayout reset() => HomeLayout.normalized(pinned: pinned);

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
