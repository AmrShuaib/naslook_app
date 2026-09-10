import 'client.dart';
import 'models.dart';

/// واجهة خادم Naslife فوق ApiClient (مسارات فعلية من src/index.js).
extension NaslifeApi on ApiClient {
  // ---- الحساب والملف
  Future<Profile> myProfile() async => Profile.fromJson(await get('/me/profile'));
  Future<Profile> updateProfile(Map<String, dynamic> patch) async => Profile.fromJson(await put('/me/profile', patch));
  Future<Profile> profileOf(String id) async => Profile.fromJson(await get('/profiles/$id'));
  Future<Person> userByHandle(String handle) async => Person.fromJson(await get('/users/$handle'));
  Future<Map<String, dynamic>> presenceOf(String id) => get('/presence/$id');
  Future<void> patchMe(Map<String, dynamic> patch) => patch_('/me', patch);

  // ---- جهات الاتصال والطلبات
  Future<List<Person>> contacts() async => asList(await getList('/contacts')).map(Person.fromJson).toList();
  Future<List<FriendRequest>> requests() async => asList(await getList('/requests')).map(FriendRequest.fromJson).toList();
  Future<Map<String, dynamic>> addContact(String handle) => post('/contacts', {'handle': handle, 'id': handle, 'nickname': handle});
  Future<void> ignoreRequest(String id) => post('/requests/$id/ignore', const {});
  Future<void> removeContact(String id) => delete('/contacts/$id');

  // ---- المحادثات
  Future<List<Chat>> chats() async => asList(await getList('/chats')).map(Chat.fromJson).toList();
  Future<List<Message>> messages(String peer) async => asList(await getList('/messages/$peer')).map(Message.fromJson).toList();
  Future<Message> sendMessage(String peer, String text) async {
    final data = await post('/messages', {'to': peer, 'recipientId': peer, 'peer': peer, 'type': 'text', 'content': text});
    final m = data['message'] is Map ? asMap(data['message']) : data;
    if (m['id'] == null) {
      return Message(id: DateTime.now().microsecondsSinceEpoch.toString(), senderId: 'me', type: 'text', content: text, sentAt: DateTime.now());
    }
    return Message.fromJson(m);
  }
  Future<void> markRead(String peer) => post('/messages/$peer/read', const {});

  // ---- الخريطة والقصص
  Future<List<Story>> stories(BBox b) async => asList(await getList('/stories', query: {'bbox': b.query})).map(Story.fromJson).toList();
  Future<Story> postStory({required String text, required double lat, required double lng, String caption = ''}) async =>
      Story.fromJson(await post('/stories', {'type': 'text', 'content': text, 'caption': caption, 'lat': lat, 'lng': lng}));
  Future<List<Presence>> mapPresence(BBox b) async => asList(await getList('/map/presence', query: {'bbox': b.query})).map(Presence.fromJson).toList();
  Future<MyPresence> myPresence() async => MyPresence.fromJson(await get('/me/map-presence'));
  Future<MyPresence> setPresence({double? lat, double? lng, String? title, bool? visible, int? hideAfterHours}) async =>
      MyPresence.fromJson(await put('/me/map-presence', {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (title != null) 'title': title,
        if (visible != null) 'visible': visible,
        if (hideAfterHours != null) 'hideAfterHours': hideAfterHours == 0 ? null : hideAfterHours,
      }));
  Future<List<Pin>> pins(BBox b) async => asList(await getList('/map/pins', query: {'bbox': b.query})).map(Pin.fromJson).toList();
  Future<Pin> dropPin({required double lat, required double lng, required String text, String? placeName, int? rating}) async =>
      Pin.fromJson(await post('/map/pins', {
        'lat': lat, 'lng': lng,
        'type': rating != null ? 'review' : 'text',
        'content': text,
        if (placeName != null) 'placeName': placeName,
        if (rating != null) 'rating': rating,
      }));
  Future<List<Business>> businesses(BBox b) async => asList(await getList('/businesses', query: {'bbox': b.query})).map(Business.fromJson).toList();

  // ---- الدوائر
  Future<List<Vessel>> myVessels() async => asList(await getList('/vessels/mine')).map(Vessel.fromJson).toList();
  Future<List<Vessel>> vessels({String q = '', String kind = 'general', bool active = true}) async =>
      asList(await getList('/vessels', query: {'q': q, 'kind': kind, if (active) 'sort': 'active'})).map(Vessel.fromJson).toList();
  Future<List<Post>> feed() async => asList(await getList('/vessels/feed')).map(Post.fromJson).toList();
  Future<(Vessel, List<Post>)> vessel(String id) async {
    final data = await get('/vessels/$id');
    return (Vessel.fromJson(data), asList(data['postsPage']).map(Post.fromJson).toList());
  }
  Future<List<Post>> vesselPosts(String id, {DateTime? before}) async =>
      asList(await getList('/vessels/$id/posts', query: {if (before != null) 'before': before.toUtc().toIso8601String()})).map(Post.fromJson).toList();
  Future<List<Person>> vesselMembers(String id) async => asList(await getList('/vessels/$id/members')).map(Person.fromJson).toList();
  Future<void> joinVessel(String id) => post('/vessels/$id/join', const {});
  Future<void> leaveVessel(String id) => post('/vessels/$id/leave', const {});
  Future<void> seenVessel(String id) => post('/vessels/$id/seen', const {});
  Future<Vessel> createVessel({required String name, required String topic, bool isPublic = true}) async =>
      Vessel.fromJson(await post('/vessels', {'name': name, 'topic': topic, 'isPublic': isPublic, 'kind': 'general'}));
  Future<Post> createPost(String vesselId, String text, {String kind = 'discussion'}) async =>
      Post.fromJson(await post('/vessels/$vesselId/posts', {'type': 'text', 'content': text, 'kind': kind}));
  Future<List<Comment>> comments(String postId) async => asList(await getList('/posts/$postId/comments')).map(Comment.fromJson).toList();
  Future<Comment> addComment(String postId, String text) async => Comment.fromJson(await post('/posts/$postId/comments', {'text': text, 'content': text}));
  Future<void> supportPost(String postId) => post('/posts/$postId/support', const {});
}
