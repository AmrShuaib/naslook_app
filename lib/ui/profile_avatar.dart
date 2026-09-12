import 'package:flutter/material.dart';

import '../api/models.dart';
import '../pages/profile/user_profile_page.dart';
export '../pages/profile/user_profile_page.dart' show openProfile;
import 'widgets.dart';

/// صورة شخصية تفتح الملف الشخصي لصاحبها عند الضغط.
class ProfileAvatar extends StatelessWidget {
  final Person person;
  final double size;
  final bool ring;
  final bool online;
  final double radius;
  const ProfileAvatar({super.key, required this.person, this.size = 44, this.ring = false, this.online = false, this.radius = -1});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'ملف ${person.nickname}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openProfile(context, person),
          child: Avatar(name: person.nickname, url: person.avatarUrl, size: size, ring: ring, online: online, radius: radius),
        ),
      );
}
