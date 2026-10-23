/// مجمّع عناصر تشغيل يُعاد استعمالها، لصوت فيديو اللحظات على سفاري iOS.
///
/// لماذا: WebKit لا يقبل تشغيل عنصر <video> بالصوت إلا داخل لمسة، ويرفع هذا القيد عن العنصر نفسه إلى الأبد متى شُغّل
/// داخل لمسة (ولو صامتاً وبلا مصدر). عنصر جديد لكل لحظة يعني رقاقة «اضغط لتشغيل الصوت» في كل لحظة؛ أما العنصر المفتوح
/// فيُعاد استعماله بمصدر جديد فتبدأ اللحظات التالية بالصوت. منطق المجمّع هنا بلا متصفح حتى يُختبر على Dart VM،
/// والويب (`video_view_web.dart`) يملؤه بعناصر <video> ويستدعي [userGesture] من داخل كل pointerup.
class MediaSlot<E> {
  final int id;
  final E element;
  /// يملكه مشغّل الآن
  bool busy = false;
  /// شُغّل داخل لمسة فرُفع عنه قيد الصوت
  bool blessed = false;
  MediaSlot(this.id, this.element);
}

class MediaSlotPool<E> {
  final E Function() create;
  /// يُستدعى داخل لمسة المستخدم على عنصر حر لم يُفتح بعد (الويب: تشغيل صامت ثم إيقاف فوري)
  final void Function(E element) bless;
  /// كم عنصراً حراً مفتوحاً نُبقي جاهزاً: اللحظة الحالية واللحظة التي تُبنى أثناء الانتقال تملكان عنصرين معاً
  final int spare;
  final _slots = <MediaSlot<E>>[];
  MediaSlotPool({required this.create, required this.bless, this.spare = 2});

  List<MediaSlot<E>> get slots => List.unmodifiable(_slots);

  MediaSlot<E>? byId(int id) {
    for (final s in _slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  MediaSlot<E> _add() {
    final s = MediaSlot<E>(_slots.length, create());
    _slots.add(s);
    return s;
  }

  /// عنصر حر للمشغّل، والمفتوح أولاً؛ وإن لم يوجد حر يُنشأ جديد (يُفتح في اللمسة التالية).
  MediaSlot<E> acquire() {
    MediaSlot<E>? pick;
    for (final s in _slots) {
      if (s.busy) continue;
      if (pick == null || (s.blessed && !pick.blessed)) pick = s;
    }
    pick ??= _add();
    pick.busy = true;
    return pick;
  }

  void release(MediaSlot<E> s) => s.busy = false;

  /// شُغّل بالصوت بنجاح (رقاقة رفع الكتم داخل لمسة): صار مفتوحاً.
  void markBlessed(MediaSlot<E> s) => s.blessed = true;

  /// من داخل لمسة المستخدم: يُبقي [spare] عناصر حرة ويفتح كل حر لم يُفتح. العنصر المشغول لا يُلمس حتى لا يتوقف ما يُعرض.
  void userGesture() {
    var free = 0;
    for (final s in _slots) {
      if (!s.busy) free++;
    }
    for (; free < spare; free++) {
      _add();
    }
    for (final s in _slots) {
      if (s.busy || s.blessed) continue;
      try {
        bless(s.element);
        s.blessed = true;
      } catch (_) {}
    }
  }
}
