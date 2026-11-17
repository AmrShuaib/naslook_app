import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../ui/launch_splash.dart';

/// جولة الترحيب: ثلاث صفحات تُعرض مرة واحدة لزائر بلا جلسة قبل واجهة الزائر أو شاشة الدخول، وتُعاد من «عن ناس لايف».
/// [onDone] يُستدعى عند «ابدأ» أو «تخطي»؛ بلا [onDone] (إعادة الجولة) تُغلق الصفحة فقط.
class WelcomeTourPage extends StatefulWidget {
  final VoidCallback? onDone;
  const WelcomeTourPage({super.key, this.onDone});

  @override
  State<WelcomeTourPage> createState() => _WelcomeTourPageState();
}

class _Chip {
  final String label, kind;
  final IconData icon;
  final Alignment at;
  const _Chip(this.label, this.kind, this.icon, this.at);
}

class _Step {
  final String title, body;
  final IconData icon, sideIcon;
  final Color color, soft, sideColor;
  final List<_Chip> chips;
  final bool logo;
  const _Step({required this.title, required this.body, required this.icon, required this.sideIcon, required this.color, required this.soft, required this.sideColor, required this.chips, this.logo = false});
}

// سطر وصفي واحد لكل صفحة: لا شعار لفظي (لم يُختر بعد) ولا اسم مدينة (التطبيق ليس خاصاً بمدينة)
const _steps = [
  _Step(
    title: 'الخريطة',
    body: 'شاهد ما يحدث حولك الآن: لحظات وعروض وفعاليات على خريطة حية.',
    icon: Icons.map_rounded, sideIcon: Icons.place_rounded, color: Joy.primary, soft: Joy.primarySoft, sideColor: Joy.accent, logo: true,
    chips: [
      _Chip('لحظة', 'moment', Icons.bolt_rounded, Alignment(-0.95, -0.7)),
      _Chip('عرض', 'offer', Icons.local_offer_rounded, Alignment(0.95, -0.15)),
      _Chip('فعالية', 'event', Icons.event_rounded, Alignment(-0.8, 0.85)),
    ],
  ),
  _Step(
    title: 'الدوائر',
    body: 'مجتمعات وأنشطة تجارية بالقرب منك: تابعها واطلب منها واحجز لديها.',
    icon: Icons.storefront_rounded, sideIcon: Icons.groups_rounded, color: Joy.green, soft: Joy.greenSoft, sideColor: Joy.primary,
    chips: [
      _Chip('متابعة', 'moment', Icons.add_rounded, Alignment(0.95, -0.75)),
      _Chip('طلب', 'market', Icons.shopping_basket_rounded, Alignment(-0.95, -0.1)),
      _Chip('حجز', 'event', Icons.confirmation_number_rounded, Alignment(0.8, 0.85)),
    ],
  ),
  _Step(
    title: 'السوق والمحادثات',
    body: 'بع واشترِ مع من حولك، وتحدث معهم مباشرة.',
    icon: Icons.shopping_bag_rounded, sideIcon: Icons.chat_bubble_rounded, color: Joy.sun, soft: Joy.sunSoft, sideColor: Joy.primary,
    chips: [
      _Chip('للبيع', 'market', Icons.sell_rounded, Alignment(-0.95, -0.7)),
      _Chip('مطلوب', 'offer', Icons.search_rounded, Alignment(0.95, -0.2)),
      _Chip('رسالة', 'moment', Icons.send_rounded, Alignment(-0.75, 0.85)),
    ],
  ),
];

class _WelcomeTourPageState extends State<WelcomeTourPage> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _finish() {
    final done = widget.onDone;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _next() {
    if (_page >= _steps.length - 1) return _finish();
    // تقليل الحركة من إعدادات النظام: انتقال فوري
    if (MediaQuery.of(context).disableAnimations) {
      _pc.jumpToPage(_page + 1);
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _steps.length - 1;
    return Scaffold(
      key: const Key('welcome-tour'),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // ارتفاع ثابت حتى لا يقفز المحتوى حين يختفي «تخطي» في الصفحة الأخيرة
          SizedBox(
            height: 52,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: last
                  ? null
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: TextButton(key: const Key('welcome-skip'), onPressed: _finish, style: TextButton.styleFrom(foregroundColor: Joy.textMuted), child: const Text('تخطي')),
                    ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _StepView(key: ValueKey('welcome-page-$i'), step: _steps[i], active: i == _page),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'صفحة ${_page + 1} من ${_steps.length}',
            child: Row(key: const Key('welcome-dots'), mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i == _page ? Joy.primary : Joy.line, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: Key(last ? 'welcome-start' : 'welcome-next'),
                onPressed: _next,
                style: FilledButton.styleFrom(backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, minimumSize: const Size(64, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(last ? 'ابدأ' : 'التالي', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StepView extends StatefulWidget {
  final _Step step;
  final bool active;
  const _StepView({super.key, required this.step, required this.active});

  @override
  State<_StepView> createState() => _StepViewState();
}

class _StepViewState extends State<_StepView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_StepView old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  // حركة دخول مرة عند ظهور الصفحة؛ مع تقليل الحركة تظهر كاملة فوراً
  void _sync() {
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else if (widget.active && _c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return LayoutBuilder(builder: (context, box) {
      // مع تكبير النص تصغر الرسمة ليبقى العنوان والسطر ظاهرين؛ وإن ضاق المكان أكثر يُمرَّر المحتوى بدل أن يطفح
      final art = (box.maxHeight * (scale > 1.3 ? 0.36 : 0.52)).clamp(96.0, 300.0);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (s.logo) ...[
                Image.asset(LaunchSplash.asset, key: const Key('welcome-logo'), height: 64, gaplessPlayback: true, semanticLabel: 'ناس لايف'),
                const SizedBox(height: 4),
              ],
              SizedBox(
                height: s.logo ? art - 40 : art,
                child: ExcludeSemantics(
                  // الرسمة بمقاس ثابت تُصغَّر كلها، فلا يكبّرها حجم خط النظام
                  child: MediaQuery.withNoTextScaling(child: FittedBox(child: _Art(step: s, t: _c))),
                ),
              ),
              const SizedBox(height: 20),
              Text(s.title, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 24, height: 1.3, fontWeight: FontWeight.w800, color: Joy.text)),
              const SizedBox(height: 8),
              Text(s.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6, color: Joy.textMuted)),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      );
    });
  }
}

/// رسمة الصفحة من ودجات فقط: قرص ملوّن بأيقونة النوع، أيقونة جانبية، ورقائق صغيرة بألوان أنواع المحتوى.
class _Art extends StatelessWidget {
  final _Step step;
  final Animation<double> t;
  const _Art({required this.step, required this.t});

  // كل عنصر يدخل في جزء من زمن الحركة فتتتابع العناصر
  double _part(double from, double to) => Curves.easeOutBack.transform(((t.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final s = step;
    return SizedBox(
      width: 300,
      height: 230,
      child: AnimatedBuilder(
        animation: t,
        builder: (context, _) {
          final main = _part(0, .6);
          return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Transform.scale(
              scale: .7 + .3 * main,
              child: Opacity(
                opacity: main.clamp(0.0, 1.0),
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(color: s.soft, shape: BoxShape.circle),
                  child: Center(
                    child: Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: s.color.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 8))]),
                      child: Icon(s.icon, size: 64, color: s.color),
                    ),
                  ),
                ),
              ),
            ),
            // الأيقونة الجانبية: الوجه الثاني للقسم (دبوس، ناس، محادثة)
            Align(
              alignment: const Alignment(0.62, 0.72),
              child: Transform.scale(
                scale: _part(.25, .8),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: s.sideColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  child: Icon(s.sideIcon, size: 28, color: Colors.white),
                ),
              ),
            ),
            for (var i = 0; i < s.chips.length; i++)
              Align(alignment: s.chips[i].at, child: _chip(s.chips[i], _part(.35 + i * .12, .85 + i * .05))),
          ]);
        },
      ),
    );
  }

  Widget _chip(_Chip c, double v) {
    final color = Joy.kindColor(c.kind);
    return Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - v)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: .35)),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(c.icon, size: 13, color: Colors.white)),
            const SizedBox(width: 6),
            Text(c.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Joy.text)),
          ]),
        ),
      ),
    );
  }
}
