import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/jobs_api.dart';
import '../../../api/jobs_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/native_io.dart' show isNativeMobile;
import '../../../core/platform.dart';
import '../../../core/share/share_stub.dart' if (dart.library.js_interop) '../../../core/share/share_web.dart' if (dart.library.io) '../../../core/share/share_io.dart' as share;
import '../../../state/app_state.dart';
import '../../../state/biz_jobs_providers.dart';
import '../../../ui/widgets.dart';
import 'business_editor.dart' show ownerErrText;

/// إحصاءات عرض واحد: قمع (أُرسل → شاهد → قبِل → أجاب → مقابلة → تعيين) بأعمدة نسبية، متوسطات الاستجابة،
/// المشاهدات، أسباب الرفض، والمراحل. التصدير CSV للباقة المتقدمة.
class JobStatsPage extends ConsumerWidget {
  final String bizId, jobId;
  final bool pro;
  const JobStatsPage({super.key, required this.bizId, required this.jobId, this.pro = false});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(apiClientProvider).exportJobCandidates(bizId, jobId);
      if (context.mounted) await showCsvDialog(context, csv);
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = (bizId: bizId, jobId: jobId);
    final data = ref.watch(jobStatsProvider(k));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(data.valueOrNull?.job?.title ?? 'الإحصاءات', overflow: TextOverflow.ellipsis),
        actions: [if (pro) IconButton(key: const Key('stats-export'), tooltip: 'تصدير CSV', onPressed: () => _export(context, ref), icon: const Icon(Icons.download_outlined))],
      ),
      body: data.when(
        data: (s) {
          final max = s.funnel.fold(0, (m, f) => f.n > m ? f.n : m);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
            const SectionTitle('القمع'),
            JoyCard(
              key: const Key('stats-funnel'),
              child: Column(children: [
                for (final f in s.funnel)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 64, child: Text(f.label, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted))),
                      Expanded(
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(8)),
                          alignment: AlignmentDirectional.centerStart,
                          // العرض نسبي لأكبر خطوة حتى تبقى الأعمدة مقروءة مهما كانت الأعداد
                          child: FractionallySizedBox(widthFactor: max == 0 ? 0 : (f.n / max).clamp(0, 1).toDouble(), child: Container(decoration: BoxDecoration(color: f.id == 'hired' ? Joy.success : Joy.primary, borderRadius: BorderRadius.circular(8)))),
                        ),
                      ),
                      SizedBox(width: 36, child: Text('${f.n}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _Stat('متوسط أيام الإجابة', s.avgDaysToAnswer == null ? '—' : s.avgDaysToAnswer!.toStringAsFixed(1), Icons.hourglass_bottom_rounded),
              _Stat('متوسط ساعات المشاهدة', s.avgHoursToView == null ? '—' : s.avgHoursToView!.toStringAsFixed(1), Icons.visibility_outlined),
              _Stat('مشاهدات العرض', '${s.views}', Icons.remove_red_eye_outlined),
            ]),
            const SizedBox(height: 6),
            const SectionTitle('حسب المرحلة'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in jobStages.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: (s.byStage[e.key] ?? 0) > 0 ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(999)),
                  child: Text('${e.value} ${s.byStage[e.key] ?? 0}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: (s.byStage[e.key] ?? 0) > 0 ? Joy.primary : Joy.textMuted)),
                ),
            ]),
            const SizedBox(height: 14),
            const SectionTitle('أسباب الرفض'),
            if (s.declines.isEmpty)
              const Text('لا رفض مسبَّب بعد.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))
            else
              JoyCard(child: Column(children: [
                for (final d in s.declines)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(d.reason.isEmpty ? 'بلا سبب' : d.reason, style: const TextStyle(fontSize: 13.5))), Text('${d.n}', style: const TextStyle(fontWeight: FontWeight.w700))])),
              ])),
            const SizedBox(height: 14),
            if (pro)
              OutlinedButton.icon(key: const Key('stats-export-btn'), onPressed: () => _export(context, ref), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('تصدير المرشحين الذين أجابوا (CSV)'))
            else if (!isIosNative)
              const Text('تصدير المرشحين إلى CSV متاح في الباقة المتقدمة.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5), textAlign: TextAlign.center),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(jobStatsProvider(k))),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(left: 6, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
          child: Column(children: [
            Icon(icon, size: 18, color: Joy.primary),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 10.5), textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// يعرض CSV المرشحين نصاً قابلاً للتحديد مع نسخ، ومشاركة أصلية على الجوال (لا حفظ ملفات على الويب بسبب CSP).
Future<void> showCsvDialog(BuildContext context, String csv) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدير المرشحين (CSV)'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(csv.isEmpty ? 'لا مرشحين أجابوا بعد.' : csv, key: const Key('csv-text'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontFamily: AppTheme.bodyFont))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          // ورقة المشاركة الأصلية (share_plus على الجوال، Web Share API على المتصفح)؛ لا معنى لها على سطح المكتب
          if (isNativeMobile || kIsWeb)
            TextButton(key: const Key('csv-share'), onPressed: () async {
              final ok = await share.nativeShare(title: 'المرشحون', text: csv, url: '');
              if (!ok && ctx.mounted) toast(ctx, 'تعذّرت المشاركة؛ انسخ النص', error: true);
            }, child: const Text('مشاركة')),
          FilledButton(
            key: const Key('csv-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (ctx.mounted) toast(ctx, 'نُسخ الجدول؛ الصقه في Excel أو Google Sheets');
            },
            child: const Text('نسخ'),
          ),
        ],
      ),
    );
