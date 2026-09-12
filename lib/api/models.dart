/// نماذج بيانات خادم Naslife. القراءة متسامحة مع camelCase وsnake_case.
String _s(Map m, List<String> keys, [String def = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null) return v.toString();
  }
  return def;
}

String? _sn(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().isNotEmpty) return v.toString();
  }
  return null;
}

double? _d(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v);
      if (p != null) return p;
    }
  }
  return null;
}

int _i(Map m, List<String> keys, [int def = 0]) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v.toInt();
    if (v is String) {
      final p = int.tryParse(v);
      if (p != null) return p;
    }
  }
  return def;
}

bool _b(Map m, List<String> keys, [bool def = false]) {
  for (final k in keys) {
    final v = m[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
  }
  return def;
}

DateTime? _t(Map m, List<String> keys) {
  final v = _sn(m, keys);
  return v == null ? null : DateTime.tryParse(v)?.toLocal();
}

List<String> _list(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is List) return v.map((e) => e.toString()).toList();
  }
  return const [];
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asList(dynamic v) =>
    v is List ? v.map(asMap).toList() : const [];

/// مستخدم مختصر (جهة اتصال، عضو، مرسل).
class Person {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final bool online;
  const Person({required this.id, required this.nickname, this.avatarUrl, this.online = false});
  factory Person.fromJson(Map m) => Person(
        id: _s(m, ['id', 'userId', 'user_id']),
        nickname: _s(m, ['nickname', 'name']),
        avatarUrl: _sn(m, ['avatarUrl', 'avatar_url', 'avatar']),
        online: _b(m, ['online']),
      );
}

class Chat {
  final Person peer;
  final String? lastType;
  final String? lastContent;
  final DateTime? lastAt;
  final bool lastMine;
  final int unread;
  const Chat({required this.peer, this.lastType, this.lastContent, this.lastAt, this.lastMine = false, this.unread = 0});
  factory Chat.fromJson(Map m) => Chat(
        peer: Person.fromJson(m),
        lastType: _sn(m, ['lastType', 'last_type']),
        lastContent: _sn(m, ['lastContent', 'last_content']),
        lastAt: _t(m, ['lastAt', 'last_at']),
        lastMine: _b(m, ['lastMine', 'last_mine']),
        unread: _i(m, ['unread']),
      );
}

enum MessageStatus { sending, failed, sent }

/// اقتباس رسالة (للرد عليها): يُحفظ في بيانات الرسالة الإضافية حتى يظهر عند الطرفين.
class MessageQuote {
  final String id, senderId, senderName, type, content;
  const MessageQuote({required this.id, required this.senderId, required this.senderName, this.type = 'text', required this.content});
  factory MessageQuote.fromJson(Map m) => MessageQuote(
        id: _s(m, ['id']), senderId: _s(m, ['senderId', 'sender_id']), senderName: _s(m, ['senderName', 'sender_name', 'nickname']),
        type: _s(m, ['type'], 'text'), content: _s(m, ['content', 'text']),
      );
  Map<String, dynamic> toJson() => {'id': id, 'senderId': senderId, 'senderName': senderName, 'type': type, 'content': content};
  String get preview => Message.previewOf(type, content);
}

class Message {
  final String id;
  final String senderId;
  /// text | image | video | audio | file
  final String type;
  /// النص، أو رابط الوسائط لغير النص.
  final String content;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  /// حالة الإرسال المحلية؛ الرسائل القادمة من الخادم دائماً sent.
  final MessageStatus status;
  /// معرّف محلي للرسالة المتفائلة حتى يرد الخادم بمعرّفها الحقيقي.
  final String? localId;
  final String? replyTo;
  final MessageQuote? quote;
  final String? forwardedFrom;
  /// بيانات إضافية (مثل durationMs للصوت، وwidth/height للصور).
  final Map<String, dynamic> extra;
  const Message({required this.id, required this.senderId, required this.type, required this.content, this.sentAt, this.deliveredAt, this.readAt,
      this.status = MessageStatus.sent, this.localId, this.replyTo, this.quote, this.forwardedFrom, this.extra = const {}});
  factory Message.fromJson(Map m) => Message(
        id: _s(m, ['id']),
        senderId: _s(m, ['sender_id', 'senderId', 'from']),
        type: _s(m, ['type'], 'text'),
        content: _s(m, ['content', 'text', 'url']),
        sentAt: _t(m, ['sent_at', 'sentAt', 'at', 'created_at', 'createdAt']),
        deliveredAt: _t(m, ['delivered_at', 'deliveredAt']),
        readAt: _t(m, ['read_at', 'readAt']),
        replyTo: _sn(m, ['reply_to', 'replyTo']),
        quote: m['quote'] is Map ? MessageQuote.fromJson(asMap(m['quote'])) : null,
        forwardedFrom: _sn(m, ['forwarded_from', 'forwardedFrom']),
        extra: asMap(m['extra']),
      );
  /// المفتاح الذي يميّز الرسالة في القوائم: معرّف الخادم إن وُجد وإلا المحلي.
  String get key => id.isNotEmpty ? id : (localId ?? '');
  bool get isPending => status != MessageStatus.sent;
  bool get isMedia => type != 'text';
  int? get durationMs => extra['durationMs'] is num ? (extra['durationMs'] as num).toInt() : null;
  String get preview => previewOf(type, content);
  static String previewOf(String type, String content) => switch (type) {
        'text' => content, 'image' => '📷 صورة', 'video' => '🎬 فيديو', 'audio' => '🎤 رسالة صوتية', _ => '📎 ملف',
      };
  Message copyWith({String? id, DateTime? sentAt, DateTime? deliveredAt, DateTime? readAt, MessageStatus? status, String? localId, String? replyTo,
      MessageQuote? quote, String? forwardedFrom, Map<String, dynamic>? extra, String? content}) => Message(
      id: id ?? this.id, senderId: senderId, type: type, content: content ?? this.content, sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt, readAt: readAt ?? this.readAt, status: status ?? this.status, localId: localId ?? this.localId,
      replyTo: replyTo ?? this.replyTo, quote: quote ?? this.quote, forwardedFrom: forwardedFrom ?? this.forwardedFrom, extra: extra ?? this.extra);
  /// دمج بيانات إضافية قادمة من /chat/meta.
  Message withMeta(Map meta) => copyWith(
        replyTo: _sn(meta, ['replyTo', 'reply_to']),
        quote: meta['quote'] is Map ? MessageQuote.fromJson(asMap(meta['quote'])) : null,
        forwardedFrom: _sn(meta, ['forwardedFrom', 'forwarded_from']),
        extra: meta['extra'] is Map ? {...extra, ...asMap(meta['extra'])} : null,
      );
}

class Story {
  final String id;
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String type;
  final String content;
  final String caption;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  const Story({required this.id, required this.userId, required this.nickname, this.avatarUrl, required this.type, required this.content, required this.caption, this.lat, this.lng, this.createdAt, this.expiresAt});
  factory Story.fromJson(Map m) => Story(
        id: _s(m, ['id']),
        userId: _s(m, ['userId', 'user_id']),
        nickname: _s(m, ['nickname']),
        avatarUrl: _sn(m, ['avatarUrl', 'avatar_url']),
        type: _s(m, ['type'], 'text'),
        content: _s(m, ['content']),
        caption: _s(m, ['caption']),
        lat: _d(m, ['lat']),
        lng: _d(m, ['lng']),
        createdAt: _t(m, ['createdAt', 'created_at']),
        expiresAt: _t(m, ['expiresAt', 'expires_at']),
      );
}

class Presence {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final double lat;
  final double lng;
  final String title;
  final bool online;
  final bool me;
  final DateTime? updatedAt;
  const Presence({required this.id, required this.nickname, this.avatarUrl, required this.lat, required this.lng, this.title = '', this.online = false, this.me = false, this.updatedAt});
  factory Presence.fromJson(Map m) => Presence(
        id: _s(m, ['id', 'userId', 'user_id']),
        nickname: _s(m, ['nickname']),
        avatarUrl: _sn(m, ['avatarUrl', 'avatar_url']),
        lat: _d(m, ['lat']) ?? 0,
        lng: _d(m, ['lng']) ?? 0,
        title: _s(m, ['title']),
        online: _b(m, ['online']),
        me: _b(m, ['me']),
        updatedAt: _t(m, ['updatedAt', 'updated_at']),
      );
}

class MyPresence {
  final double? lat;
  final double? lng;
  final String title;
  final bool visible;
  final int? hideAfterHours;
  final DateTime? expiresAt;
  const MyPresence({this.lat, this.lng, this.title = '', this.visible = false, this.hideAfterHours, this.expiresAt});
  factory MyPresence.fromJson(Map m) => MyPresence(
        lat: _d(m, ['lat']),
        lng: _d(m, ['lng']),
        title: _s(m, ['title']),
        visible: _b(m, ['visible']),
        hideAfterHours: m['hideAfterHours'] is num ? (m['hideAfterHours'] as num).toInt() : null,
        expiresAt: _t(m, ['expiresAt', 'expires_at']),
      );
}

class Pin {
  final String id;
  final String ownerId;
  final String ownerNickname;
  final String? ownerAvatar;
  final double lat;
  final double lng;
  final String type;
  final String content;
  final String? placeName;
  final int? rating;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  const Pin({required this.id, required this.ownerId, required this.ownerNickname, this.ownerAvatar, required this.lat, required this.lng, required this.type, required this.content, this.placeName, this.rating, this.createdAt, this.expiresAt});
  factory Pin.fromJson(Map m) {
    final owner = asMap(m['owner']);
    return Pin(
      id: _s(m, ['id']),
      ownerId: _s(m, ['ownerId', 'owner_id']).isNotEmpty ? _s(m, ['ownerId', 'owner_id']) : _s(owner, ['id']),
      ownerNickname: _sn(m, ['ownerNickname', 'owner_nickname', 'nickname']) ?? _s(owner, ['nickname']),
      ownerAvatar: _sn(m, ['ownerAvatar', 'owner_avatar', 'avatarUrl']) ?? _sn(owner, ['avatarUrl', 'avatar_url']),
      lat: _d(m, ['lat']) ?? 0,
      lng: _d(m, ['lng']) ?? 0,
      type: _s(m, ['type'], 'text'),
      content: _s(m, ['content']),
      placeName: _sn(m, ['placeName', 'place_name']),
      rating: m['rating'] is num ? (m['rating'] as num).toInt() : null,
      createdAt: _t(m, ['createdAt', 'created_at']),
      expiresAt: _t(m, ['expiresAt', 'expires_at']),
    );
  }
}

class Vessel {
  final String id;
  final String name;
  final String topic;
  final String kind;
  final bool isPublic;
  final int members;
  final String? role;
  final bool member;
  final DateTime? lastPostAt;
  final String? ownerId;
  const Vessel({required this.id, required this.name, required this.topic, required this.kind, this.isPublic = true, this.members = 0, this.role, this.member = false, this.lastPostAt, this.ownerId});
  factory Vessel.fromJson(Map m) {
    final role = _sn(m, ['role', 'myRole', 'my_role']);
    return Vessel(
      id: _s(m, ['id']),
      name: _s(m, ['name', 'title']),
      topic: _s(m, ['topic', 'description']),
      kind: _s(m, ['kind'], 'general'),
      isPublic: _b(m, ['isPublic', 'is_public'], true),
      members: _i(m, ['members', 'memberCount', 'member_count']),
      role: role,
      member: _b(m, ['member', 'isMember', 'is_member', 'joined']) || (role != null && role.isNotEmpty),
      lastPostAt: _t(m, ['lastPostAt', 'last_post_at']),
      ownerId: _sn(m, ['ownerId', 'owner_id']),
    );
  }
}

class Post {
  final String id;
  final String vesselId;
  final String? vesselName;
  final Person author;
  final String type;
  final String content;
  final String caption;
  final String kind;
  final String? tag;
  final int comments;
  final int supports;
  final bool supported;
  final bool unread;
  final DateTime? createdAt;
  const Post({required this.id, required this.vesselId, this.vesselName, required this.author, required this.type, required this.content, required this.caption, required this.kind, this.tag, this.comments = 0, this.supports = 0, this.supported = false, this.unread = false, this.createdAt});
  factory Post.fromJson(Map m) {
    final a = asMap(m['author']);
    final author = a.isNotEmpty
        ? Person.fromJson(a)
        : Person(id: _s(m, ['authorId', 'author_id']), nickname: _s(m, ['authorNickname', 'author_nickname', 'nickname']), avatarUrl: _sn(m, ['authorAvatar', 'author_avatar']));
    return Post(
      id: _s(m, ['id']),
      vesselId: _s(m, ['vesselId', 'vessel_id']),
      vesselName: _sn(m, ['vesselName', 'vessel_name']),
      author: author,
      type: _s(m, ['type'], 'text'),
      content: _s(m, ['content']),
      caption: _s(m, ['caption']),
      kind: _s(m, ['kind'], 'discussion'),
      tag: _sn(m, ['tag']),
      comments: _i(m, ['comments', 'commentCount', 'comment_count']),
      supports: _i(m, ['supports', 'supportCount', 'support_count', 'likes']),
      supported: _b(m, ['supported', 'mine_support', 'liked']),
      unread: _b(m, ['unread']),
      createdAt: _t(m, ['createdAt', 'created_at']),
    );
  }
}

class Comment {
  final String id;
  final Person author;
  final String text;
  final DateTime? createdAt;
  const Comment({required this.id, required this.author, required this.text, this.createdAt});
  factory Comment.fromJson(Map m) {
    final a = asMap(m['author']);
    return Comment(
      id: _s(m, ['id']),
      author: a.isNotEmpty ? Person.fromJson(a) : Person(id: _s(m, ['authorId', 'author_id']), nickname: _s(m, ['nickname', 'authorNickname'])),
      text: _s(m, ['text', 'content']),
      createdAt: _t(m, ['createdAt', 'created_at']),
    );
  }
}

class Offering {
  final String name;
  final String description;
  final String? imageUrl;
  const Offering({required this.name, required this.description, this.imageUrl});
  factory Offering.fromJson(Map m) => Offering(name: _s(m, ['name']), description: _s(m, ['description']), imageUrl: _sn(m, ['imageUrl', 'image_url']));
  Map<String, dynamic> toJson() => {'name': name, 'description': description, if (imageUrl != null) 'imageUrl': imageUrl};
}

class Profile {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String bio;
  final List<String> skills;
  final List<String> hobbies;
  final List<String> lookingFor;
  final List<Offering> offerings;
  final String accountType;
  final bool isPublic;
  final DateTime? createdAt;
  const Profile({required this.id, required this.nickname, this.avatarUrl, this.bio = '', this.skills = const [], this.hobbies = const [], this.lookingFor = const [], this.offerings = const [], this.accountType = 'personal', this.isPublic = true, this.createdAt});
  factory Profile.fromJson(Map m) {
    final u = asMap(m['user']);
    return Profile(
      id: _sn(m, ['id', 'userId', 'user_id']) ?? _s(u, ['id']),
      nickname: _sn(m, ['nickname']) ?? _s(u, ['nickname']),
      avatarUrl: _sn(m, ['avatarUrl', 'avatar_url']) ?? _sn(u, ['avatarUrl', 'avatar_url']),
      bio: _s(m, ['bio']),
      skills: _list(m, ['skills']),
      hobbies: _list(m, ['hobbies']),
      lookingFor: _list(m, ['lookingFor', 'looking_for']),
      offerings: asList(m['offerings']).map(Offering.fromJson).toList(),
      accountType: _s(m, ['accountType', 'account_type'], 'personal'),
      isPublic: _b(m, ['isPublic', 'is_public'], true),
      createdAt: _t(m, ['createdAt', 'created_at']) ?? _t(u, ['createdAt', 'created_at']),
    );
  }
}

/// طلب مراسلة: شخص راسلك وليس في جهات اتصالك بعد (GET /requests).
class FriendRequest {
  final String id;
  final Person from;
  final DateTime? createdAt;
  final String? lastContent;
  final int unread;
  const FriendRequest({required this.id, required this.from, this.createdAt, this.lastContent, this.unread = 0});
  factory FriendRequest.fromJson(Map m) {
    final f = asMap(m['from']);
    final from = f.isNotEmpty ? Person.fromJson(f) : Person(id: _s(m, ['fromId', 'from_id', 'senderId', 'sender_id', 'id']), nickname: _s(m, ['nickname', 'fromNickname']), avatarUrl: _sn(m, ['avatarUrl', 'avatar_url']));
    return FriendRequest(
      id: from.id,
      from: from,
      createdAt: _t(m, ['lastAt', 'last_at', 'createdAt', 'created_at', 'sentAt']),
      lastContent: _sn(m, ['lastContent', 'last_content']),
      unread: _i(m, ['unread']),
    );
  }
}

class Business {
  final String id;
  final String name;
  final String category;
  final String description;
  final double? lat;
  final double? lng;
  final bool verified;
  final int followers;
  final String? ownerId;
  final String? vesselId;
  const Business({required this.id, required this.name, required this.category, required this.description, this.lat, this.lng, this.verified = false, this.followers = 0, this.ownerId, this.vesselId});
  factory Business.fromJson(Map m) => Business(
        id: _s(m, ['id']),
        name: _s(m, ['name']),
        category: _s(m, ['category']),
        description: _s(m, ['description', 'about']),
        lat: _d(m, ['lat']),
        lng: _d(m, ['lng']),
        verified: _b(m, ['verified']),
        followers: _i(m, ['followers']),
        ownerId: _sn(m, ['ownerId', 'owner_id']),
        vesselId: _sn(m, ['vesselId', 'vessel_id']),
      );
}

/// حدود الخريطة كما يتوقعها الخادم: minLng,minLat,maxLng,maxLat
class BBox {
  final double minLng, minLat, maxLng, maxLat;
  const BBox(this.minLng, this.minLat, this.maxLng, this.maxLat);
  String get query => '$minLng,$minLat,$maxLng,$maxLat';
  static const jeddah = BBox(38.95, 21.25, 39.45, 21.85);
}
