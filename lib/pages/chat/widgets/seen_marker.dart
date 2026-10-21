import 'package:flutter/material.dart';

import '../../../api/models.dart';
import '../../../core/app_theme.dart';
import '../../../ui/widgets.dart';

/// علامة «شوهدت» تحت آخر رسالة لي قرأها الطرف الآخر: صورته بحجم 16 نقطة والكلمة بجانبها.
class SeenMarker extends StatelessWidget {
  final Person peer;
  const SeenMarker({super.key, required this.peer});

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('seen-marker'),
        padding: const EdgeInsetsDirectional.only(top: 3, end: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('شوهدت', style: TextStyle(fontSize: 10.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Avatar(name: peer.nickname, url: peer.avatarUrl, size: 16),
        ]),
      );
}
