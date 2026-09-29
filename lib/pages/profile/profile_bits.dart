import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../core/app_theme.dart';

/// أيقونة نوع الرابط في الملف.
IconData profileLinkIcon(String kind) => switch (kind) {
      'instagram' => Icons.photo_camera_outlined,
      'x' => Icons.tag_rounded,
      'tiktok' => Icons.music_note_rounded,
      'snapchat' => Icons.emoji_emotions_outlined,
      'website' => Icons.language_rounded,
      _ => Icons.link_rounded,
    };

/// رقاقة صغيرة ملوّنة (مهارة، شارة ثقة، وسم).
class ProfileChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color bg, fg;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const ProfileChip(this.text, {super.key, this.icon, this.bg = Joy.primarySoft, this.fg = Joy.primary, this.onTap, this.onDelete});
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (onDelete != null) ...[const SizedBox(width: 4), InkWell(onTap: onDelete, child: Icon(Icons.close_rounded, size: 15, color: fg))],
      ]),
    );
    return onTap == null ? chip : InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: chip);
  }
}

/// عمود رقم وتسمية في صف الأرقام.
class StatCell extends StatelessWidget {
  final String value, label;
  final Key? cellKey;
  const StatCell(this.value, this.label, {super.key, this.cellKey});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(key: cellKey, children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: Joy.text)),
          Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

/// مجموعة رقاقات تحت عنوان صغير (مهاراته، هواياته…).
class ChipGroup extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color bg, fg;
  const ChipGroup(this.title, this.items, {super.key, this.bg = Joy.primarySoft, this.fg = Joy.primary});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Joy.textMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in items) ProfileChip(s, bg: bg, fg: fg)]),
        ]),
      );
}

/// غلاف الملف: الصورة إن وُجدت وإلا تدرّج فيروزي.
class CoverBox extends StatelessWidget {
  final String? url;
  final double height;
  final Widget? child;
  const CoverBox({super.key, this.url, this.height = 160, this.child});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0A6E78), Color(0xFF12A0AE)])),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (url != null && url!.isNotEmpty) Image.network(mediaUrl(url!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          // تدرّج خفيف أسفل الغلاف حتى تبقى الأزرار البيضاء مقروءة على أي صورة
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black26, Colors.transparent, Colors.black26]))),
          if (child != null) child!,
        ]),
      );
}

/// زر دائري أبيض على الغلاف.
class CoverButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  const CoverButton({super.key, required this.icon, required this.tooltip, this.onTap, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: .28),
        shape: const CircleBorder(),
        child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: color, size: 20), constraints: const BoxConstraints(minWidth: 40, minHeight: 40), padding: EdgeInsets.zero),
      );
}
