import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../api/profile_v2_api.dart';
import '../../api/profile_v2_models.dart';
import '../../api/session.dart';
import '../../core/app_theme.dart';
import '../../core/media/pick_image.dart';
import '../../core/media/voice_record.dart';
import '../../state/app_state.dart';
import '../../state/profile_v2_providers.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart' show errText;
import 'intro_card.dart';
import 'profile_bits.dart';

/// الحدود: صوت التعريف 60 ثانية، فيديو التعريف 30 ثانية.
const introVoiceMax = Duration(seconds: 60);
const introVideoMaxSec = 30;
const _maxSkills = 8;

/// شاشة «تعديل الملف»: الغلاف والصورة (تُرفعان فوراً)، الاسم المعروض، اسم المستخدم بفحص التوفر، النبذة (160)،
/// «عرّف بنفسك» صوتاً أو فيديو (يُحفظ فوراً)، نوع الحساب والمسمى، المدينة والحي، المهارات، الروابط (3)، والرقم SA ثابت.
/// «حفظ» يرسل حقول النواة إلى PUT /me/profile وحقول v2 إلى PUT /me/profile/v2.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _Link {
  String kind;
  final TextEditingController ctl;
  _Link(this.kind, [String value = '']) : ctl = TextEditingController(text: value);
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  final _job = TextEditingController();
  String _accountType = 'personal';
  String? _city, _district;
  List<String> _skills = [], _hobbies = [], _lookingFor = [];
  final _links = <_Link>[];
  String? _coverUrl, _avatar;
  bool _hydratedCore = false, _hydratedV2 = false, _busyAvatar = false, _busyCover = false, _saving = false;

  // فحص اسم المستخدم
  Timer? _handleTimer;
  HandleCheck? _handleCheck;
  bool _checkingHandle = false;
  String _originalHandle = '';

  // «عرّف بنفسك»
  ProfileIntro? _intro;
  String? _introMode;
  bool _replacingIntro = false, _recording = false, _introBusy = false;
  VoiceRecordSession? _rec;
  Timer? _recTimer;
  Duration _elapsed = Duration.zero;
  RecordedVoice? _take;

  @override
  void initState() {
    super.initState();
    final me = ref.read(appStateProvider).user;
    _originalHandle = me?.nickname ?? '';
    _handle.text = _originalHandle;
    _avatar = me?.avatarUrl;
    _handle.addListener(_onHandleChanged);
  }

  @override
  void dispose() {
    _handleTimer?.cancel();
    _recTimer?.cancel();
    _rec?.dispose();
    for (final c in [_name, _handle, _bio, _job]) {
      c.dispose();
    }
    for (final l in _links) {
      l.ctl.dispose();
    }
    super.dispose();
  }

  void _hydrateCore(Profile p) {
    _hydratedCore = true;
    _bio.text = p.bio;
    _skills = [...p.skills];
    _hobbies = [...p.hobbies];
    _lookingFor = [...p.lookingFor];
    _accountType = p.accountType == 'pro' ? 'pro' : 'personal';
    _avatar = p.avatarUrl ?? _avatar;
    if (p.nickname.isNotEmpty && _originalHandle.isEmpty) {
      _originalHandle = p.nickname;
      _handle.text = p.nickname;
    }
  }

  void _hydrateV2(ProfileV2? p) {
    _hydratedV2 = true;
    if (p == null) return;
    _name.text = p.displayName;
    _job.text = p.jobTitle;
    _city = p.city.isEmpty ? null : p.city;
    _district = p.district.isEmpty ? null : p.district;
    _coverUrl = p.coverUrl;
    _intro = p.intro;
    _links.addAll([for (final l in p.links) _Link(l.kind, l.value)]);
    if (p.accountType == 'pro') _accountType = 'pro';
  }

  @override
  Widget build(BuildContext context) {
    final core = ref.watch(profileProvider);
    final v2 = ref.watch(myProfileV2Provider);
    if (!_hydratedCore && core.hasValue) _hydrateCore(core.value!);
    if (!_hydratedV2 && v2.hasValue) _hydrateV2(v2.value);
    final me = ref.watch(appStateProvider.select((s) => s.user));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        leadingWidth: 80,
        leading: TextButton(key: const Key('edit-cancel'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('إلغاء')),
        title: const Text('تعديل الملف'),
        actions: [
          TextButton(key: const Key('edit-save'), onPressed: _saving ? null : _save, child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ', style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // الغلاف والصورة
          Stack(clipBehavior: Clip.none, children: [
            CoverBox(
              url: _coverUrl,
              height: 140,
              child: Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_coverUrl != null) TextButton(key: const Key('edit-cover-remove'), style: TextButton.styleFrom(foregroundColor: Colors.white), onPressed: _busyCover ? null : () => setState(() => _coverUrl = null), child: const Text('إزالة')),
                    FilledButton.tonalIcon(
                      key: const Key('edit-cover'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .92), foregroundColor: Joy.text, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      onPressed: _busyCover ? null : _changeCover,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_busyCover ? 'جارٍ الرفع…' : 'تغيير الغلاف'),
                    ),
                  ]),
                ),
              ),
            ),
            PositionedDirectional(bottom: -36, start: 20, child: Avatar(name: me?.nickname ?? '', url: _avatar, size: 84, ring: true)),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(116, 6, 20, 0),
            child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              // صورة الحساب: تُرفع وتُثبَّت فوراً، بمعزل عن زر الحفظ
              TextButton.icon(
                key: const Key('edit-avatar'),
                onPressed: _busyAvatar ? null : _changeAvatar,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_busyAvatar ? 'جارٍ الرفع…' : (_avatar == null || _avatar!.isEmpty ? 'إضافة صورة' : 'تغيير الصورة')),
              ),
              if (_avatar != null && _avatar!.isNotEmpty)
                TextButton.icon(key: const Key('edit-avatar-remove'), onPressed: _busyAvatar ? null : _removeAvatar, style: TextButton.styleFrom(foregroundColor: Joy.danger), icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('إزالة الصورة')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('الاسم المعروض'),
              TextField(key: const Key('edit-name'), controller: _name, maxLength: 40, decoration: const InputDecoration(hintText: 'اسمك كما يظهر للناس', counterText: '')),
              const SizedBox(height: 14),
              _label('اسم المستخدم'),
              TextField(
                key: const Key('edit-handle'),
                controller: _handle,
                maxLength: 20,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(prefixText: '@ ', counterText: '', helperText: 'naslife.app/u/${_handle.text.trim().toLowerCase()}', helperStyle: const TextStyle(fontSize: 11.5, color: Joy.textMuted)),
              ),
              if (_checkingHandle || _handleCheck != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _checkingHandle ? 'جارٍ الفحص…' : _handleCheck!.text,
                    key: const Key('handle-status'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _checkingHandle ? Joy.textMuted : (_handleCheck!.available ? Joy.success : Joy.danger)),
                  ),
                ),
              const SizedBox(height: 14),
              _label('النبذة'),
              TextField(key: const Key('edit-bio'), controller: _bio, maxLength: 160, maxLines: 3, decoration: const InputDecoration(hintText: 'من أنت وماذا تقدّم')),
              const SizedBox(height: 10),
              _label('عرّف بنفسك بصوتك أو بفيديو', hint: 'اختياري · يظهر أعلى ملفك'),
              _introSection(me?.nickname ?? ''),
              const SizedBox(height: 18),
              _label('نوع الحساب'),
              Row(children: [
                Expanded(child: _AccountCard(key: const Key('acct-personal'), selected: _accountType == 'personal', title: 'شخصي', subtitle: 'منشورات وأصدقاء وسوق', onTap: () => setState(() => _accountType = 'personal'))),
                const SizedBox(width: 10),
                Expanded(child: _AccountCard(key: const Key('acct-pro'), selected: _accountType == 'pro', title: 'مهني', subtitle: '+ خدمات وحجز ومعرض أعمال', onTap: () => setState(() => _accountType = 'pro'))),
              ]),
              if (_accountType == 'pro') ...[
                const SizedBox(height: 10),
                _label('المسمى المهني (يظهر بجانب الاسم)'),
                TextField(key: const Key('edit-job'), controller: _job, maxLength: 40, decoration: const InputDecoration(hintText: 'مصوّر، مدرّب، مستشار…', counterText: '')),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('المدينة'), _cityField()])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('الحي'), _districtField()])),
              ]),
              const SizedBox(height: 16),
              _label('المهارات (حتى $_maxSkills)'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in _skills) ProfileChip(s, onDelete: () => setState(() => _skills.remove(s))),
                if (_skills.length < _maxSkills) ProfileChip('+ إضافة', key: const Key('skill-add'), bg: Joy.surface2, fg: Joy.text, onTap: _addSkill),
              ]),
              const SizedBox(height: 16),
              _label('الروابط (حتى 3)', hint: 'الحجز والدفع يبقيان داخل ناس لايف؛ الروابط للتعريف فقط.'),
              for (final (i, l) in _links.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    DropdownButton<String>(
                      key: Key('link-kind-$i'),
                      value: l.kind,
                      underline: const SizedBox(),
                      items: [for (final e in profileLinkKinds.entries) DropdownMenuItem(value: e.key, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(profileLinkIcon(e.key), size: 18, color: Joy.primary), const SizedBox(width: 6), Text(e.value, style: const TextStyle(fontSize: 13))]))],
                      onChanged: (v) => setState(() => l.kind = v ?? 'other'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(key: Key('link-value-$i'), controller: l.ctl, textDirection: TextDirection.ltr, decoration: InputDecoration(hintText: _linkHint(l.kind), isDense: true))),
                    IconButton(key: Key('link-remove-$i'), tooltip: 'حذف الرابط', onPressed: () => setState(() => _links.removeAt(i).ctl.dispose()), icon: const Icon(Icons.close_rounded, color: Joy.textMuted)),
                  ]),
                ),
              if (_links.length < 3) TextButton.icon(key: const Key('link-add'), onPressed: () => setState(() => _links.add(_Link('instagram'))), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('إضافة رابط')),
              const SizedBox(height: 14),
              JoyCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.badge_outlined, color: Joy.textMuted),
                  const SizedBox(width: 10),
                  Expanded(child: Text('الرقم ${me?.id ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  const Text('ثابت ولا يُعدَّل', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _label(String t, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          if (hint != null) Text(hint, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        ]),
      );

  String _linkHint(String kind) => switch (kind) { 'instagram' || 'x' || 'tiktok' || 'snapchat' => 'اسم الحساب بلا @', 'website' => 'example.com', _ => 'https://…' };

  Widget _cityField() {
    final cities = [...profileCities.keys, if (_city != null && !profileCities.containsKey(_city)) _city!];
    // المفتاح الخارجي يعيد بناء الحقل حين تصل القيمة من الخادم (initialValue يُقرأ عند الإنشاء فقط)
    return KeyedSubtree(
      key: ValueKey('city-${_city ?? ''}'),
      child: DropdownButtonFormField<String>(
        key: const Key('edit-city'),
        initialValue: _city,
        isExpanded: true,
        hint: const Text('اختر'),
        items: [for (final c in cities) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() { _city = v; _district = null; }),
      ),
    );
  }

  Widget _districtField() {
    final list = [...?profileCities[_city], if (_district != null && !(profileCities[_city]?.contains(_district) ?? false)) _district!];
    return KeyedSubtree(
      key: ValueKey('district-${_city ?? ''}-${_district ?? ''}'),
      child: DropdownButtonFormField<String>(
        key: const Key('edit-district'),
        initialValue: _district,
        isExpanded: true,
        hint: const Text('اختر'),
        items: [for (final d in list) DropdownMenuItem(value: d, child: Text(d))],
        onChanged: _city == null ? null : (v) => setState(() => _district = v),
      ),
    );
  }

  // ---- «عرّف بنفسك»

  Widget _introSection(String nickname) {
    final intro = _intro;
    if (intro != null && !_replacingIntro) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProfileIntroCard(name: nickname, intro: intro, owner: true),
        Row(children: [
          Expanded(child: TextButton.icon(key: const Key('intro-replace'), onPressed: () => setState(() { _replacingIntro = true; _introMode = intro.kind; _take = null; }), icon: Icon(intro.isVideo ? Icons.videocam_outlined : Icons.mic_none_rounded, size: 18), label: Text(intro.isVideo ? 'إعادة التصوير' : 'إعادة التسجيل', maxLines: 1, overflow: TextOverflow.ellipsis))),
          TextButton(key: const Key('intro-delete'), style: TextButton.styleFrom(foregroundColor: Joy.danger), onPressed: _introBusy ? null : _deleteIntro, child: const Text('حذف')),
        ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _ModeCard(key: const Key('intro-voice'), icon: Icons.mic_rounded, title: 'تسجيل صوتي', subtitle: 'حتى 60 ثانية', selected: _introMode == 'voice', onTap: () => setState(() => _introMode = 'voice'))),
        const SizedBox(width: 10),
        Expanded(child: _ModeCard(key: const Key('intro-video'), icon: Icons.videocam_rounded, title: 'فيديو قصير', subtitle: 'حتى 30 ثانية · أفقي', selected: _introMode == 'video', onTap: () => setState(() => _introMode = 'video'))),
      ]),
      if (_introMode == 'voice') ...[const SizedBox(height: 10), _voiceBox()],
      if (_introMode == 'video') ...[const SizedBox(height: 10), _videoBox()],
      if (intro != null && _replacingIntro)
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(key: const Key('intro-keep'), onPressed: () => setState(() { _replacingIntro = false; _introMode = null; _take = null; }), child: const Text('إبقاء الحالي'))),
      const SizedBox(height: 4),
      const Text('يمكن قصره على الأصدقاء من «التوثيق والتحكم».', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)),
    ]);
  }

  Widget _voiceBox() {
    final take = _take;
    return JoyCard(
      key: const Key('intro-voice-box'),
      child: take == null
          ? Column(children: [
              Material(
                color: _recording ? Joy.danger : Joy.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  key: Key(_recording ? 'intro-stop' : 'intro-record'),
                  customBorder: const CircleBorder(),
                  onTap: _recording ? _stopRecording : _startRecording,
                  child: SizedBox(width: 72, height: 72, child: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 36)),
                ),
              ),
              const SizedBox(height: 10),
              Text(_recording ? 'جارٍ التسجيل… اضغط للإيقاف' : 'اضغط للتسجيل', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('من أنت، وماذا تقدّم، وأين تعمل. حتى 60 ثانية.', style: TextStyle(color: Joy.textMuted, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('${clockText(_elapsed.inSeconds)} / ${clockText(introVoiceMax.inSeconds)}', key: const Key('intro-timer'), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: _recording ? Joy.danger : Joy.textMuted)),
              if (_recording) const Text('يتوقف تلقائياً عند الدقيقة', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('استمع قبل الاعتماد', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              IntroVoiceBar(bytes: take.bytes, mime: take.mime, sec: take.duration.inSeconds, playKey: const Key('intro-preview-play')),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: OutlinedButton(key: const Key('intro-rerecord'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: _introBusy ? null : () => setState(() { _take = null; _elapsed = Duration.zero; }), child: const Text('إعادة التسجيل'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(key: const Key('intro-use'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: _introBusy ? null : _useVoice, child: Text(_introBusy ? 'جارٍ الرفع…' : 'اعتماد'))),
              ]),
            ]),
    );
  }

  Widget _videoBox() => JoyCard(
        key: const Key('intro-video-box'),
        child: Column(children: [
          const Icon(Icons.videocam_rounded, size: 40, color: Joy.primary),
          const SizedBox(height: 6),
          const Text('صوّر فيديو قصيراً', style: TextStyle(fontWeight: FontWeight.w700)),
          const Text('أفقي، حتى 30 ثانية. أو اختر من الاستوديو.', style: TextStyle(color: Joy.textMuted, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          if (_introBusy)
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else
            Row(children: [
              Expanded(child: FilledButton.icon(key: const Key('intro-video-camera'), style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => _pickVideo(gallery: false), icon: const Icon(Icons.videocam_outlined, size: 18), label: const Text('تصوير'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(key: const Key('intro-video-gallery'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => _pickVideo(gallery: true), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('من الاستوديو'))),
            ]),
        ]),
      );

  Future<void> _startRecording() async {
    if (_recording) return;
    final rec = _rec ??= VoiceRecordSession();
    try {
      await rec.start();
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return;
      toast(context, 'تعذر بدء التسجيل: ${e.toString().replaceFirst('Bad state: ', '')}', error: true);
      return;
    }
    if (!mounted) return;
    setState(() { _recording = true; _elapsed = Duration.zero; _take = null; });
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() => _elapsed = rec.elapsed);
      // يتوقف تلقائياً عند الحد
      if (_elapsed >= introVoiceMax) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    final rec = _rec;
    if (!_recording || rec == null) return;
    setState(() => _recording = false);
    try {
      final v = await rec.stop();
      if (v == null || v.duration < const Duration(seconds: 1)) {
        if (mounted) toast(context, 'التسجيل قصير جداً؛ تكلّم ثانية على الأقل');
        return;
      }
      if (mounted) setState(() { _take = v; _elapsed = v.duration; });
    } catch (e) {
      if (mounted) toast(context, 'تعذر حفظ التسجيل', error: true);
    }
  }

  Future<void> _useVoice() async {
    final t = _take;
    if (t == null) return;
    final sec = t.duration.inSeconds.clamp(1, introVoiceMax.inSeconds);
    await _saveIntro(bytes: t.bytes, mime: t.mime, name: t.name, kind: 'voice', sec: sec);
  }

  Future<void> _pickVideo({required bool gallery}) async {
    PickedVideo? v;
    try {
      v = await pickVideo(gallery: gallery, maxDuration: const Duration(seconds: introVideoMaxSec));
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return;
      toast(context, errText(e), error: true);
      return;
    }
    if (v == null || !mounted) return;
    if (v.durationSec != null && v.durationSec! > introVideoMaxSec) {
      toast(context, 'الفيديو أطول من $introVideoMaxSec ثانية؛ اختر مقطعاً أقصر', error: true);
      return;
    }
    // المدة المجهولة (الويب) تُترك للخادم ليتحقق منها؛ نمرر الحد الأقصى
    await _saveIntro(bytes: v.bytes, mime: v.mime, name: v.name, kind: 'video', sec: (v.durationSec ?? introVideoMaxSec).clamp(1, introVideoMaxSec));
  }

  Future<void> _saveIntro({required Uint8List bytes, required String mime, required String name, required String kind, required int sec}) async {
    setState(() => _introBusy = true);
    try {
      final api = ref.read(apiClientProvider);
      final up = await api.uploadMedia(bytes, contentType: mime, fileName: name);
      final intro = await api.setIntro(kind: kind, url: up.url, sec: sec);
      ref.invalidate(myProfileV2Provider);
      if (!mounted) return;
      setState(() { _intro = intro; _replacingIntro = false; _introMode = null; _take = null; });
      toast(context, kind == 'voice' ? 'حُفظ تعريفك الصوتي' : 'حُفظ فيديو تعريفك');
    } catch (e) {
      if (mounted) toast(context, e is ApiException && e.body?['error'] == 'bad-intro' ? 'التسجيل غير مقبول: صوت حتى 60 ثانية أو فيديو حتى 30 ثانية' : errText(e), error: true);
    } finally {
      if (mounted) setState(() => _introBusy = false);
    }
  }

  Future<void> _deleteIntro() async {
    setState(() => _introBusy = true);
    try {
      await ref.read(apiClientProvider).deleteIntro();
      ref.invalidate(myProfileV2Provider);
      if (mounted) setState(() { _intro = null; _introMode = null; _take = null; });
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _introBusy = false);
    }
  }

  // ---- الصورة والغلاف

  Future<void> _changeAvatar() async {
    setState(() => _busyAvatar = true);
    try {
      final img = await pickImage();
      if (img == null) return;
      final api = ref.read(apiClientProvider);
      final up = await api.uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      final url = await api.setAvatar(up.url);
      await _applyAvatar(url);
      if (mounted) toast(context, 'حُدّثت صورتك');
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return;
      toast(context, e.toString().contains('unsupported') ? 'الخادم لا يدعم صور الحساب بعد' : errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _busyAvatar = true);
    try {
      await ref.read(apiClientProvider).clearAvatar();
      await _applyAvatar(null);
      if (mounted) toast(context, 'أُزيلت صورتك');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  /// يثبّت الصورة في الجلسة (تظهر فوراً في كل الشاشات) ويعيد جلب الملف.
  Future<void> _applyAvatar(String? url) async {
    final u = ref.read(appStateProvider).user;
    if (u != null) await ref.read(appStateProvider.notifier).updateUser(SessionUser(id: u.id, nickname: u.nickname, displayName: u.displayName, avatarUrl: url));
    ref.invalidate(profileProvider);
    ref.invalidate(myProfileV2Provider);
    if (mounted) setState(() => _avatar = url);
  }

  Future<void> _changeCover() async {
    setState(() => _busyCover = true);
    try {
      final img = await pickImage();
      if (img == null) return;
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => _coverUrl = up.url);
    } catch (e) {
      if (!mounted || handlePermissionError(context, e)) return;
      toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyCover = false);
    }
  }

  // ---- اسم المستخدم والمهارات والحفظ

  void _onHandleChanged() {
    final h = _handle.text.trim().toLowerCase();
    _handleTimer?.cancel();
    if (h == _originalHandle.toLowerCase() || h.isEmpty) {
      // الاسم الحالي أو فارغ: لا فحص، ونحدّث سطر الرابط فقط
      setState(() { _handleCheck = null; _checkingHandle = false; });
      return;
    }
    setState(() { _checkingHandle = true; _handleCheck = null; });
    _handleTimer = Timer(const Duration(milliseconds: 400), () async {
      HandleCheck r;
      try {
        r = await ref.read(apiClientProvider).checkHandle(h);
      } catch (_) {
        r = const HandleCheck(valid: false, available: false, reason: 'error');
      }
      if (!mounted || _handle.text.trim().toLowerCase() != h) return;
      setState(() { _checkingHandle = false; _handleCheck = r; });
    });
  }

  Future<void> _addSkill() async {
    final s = await askText(context, title: 'مهارة جديدة', hint: 'تصوير منتجات، مونتاج…', confirm: 'إضافة', maxLines: 1);
    if (s == null || s.isEmpty || !mounted) return;
    if (_skills.contains(s) || _skills.length >= _maxSkills) return;
    setState(() => _skills.add(s));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    try {
      await api.updateProfile({'bio': _bio.text.trim(), 'skills': _skills, 'hobbies': _hobbies, 'lookingFor': _lookingFor, 'accountType': _accountType});
      try {
        await api.updateProfileV2({
          'displayName': _name.text.trim(),
          'jobTitle': _accountType == 'pro' ? _job.text.trim() : '',
          'city': _city ?? '',
          'district': _city == null ? '' : (_district ?? ''),
          'coverUrl': _coverUrl,
          'links': [for (final l in _links) if (l.ctl.text.trim().isNotEmpty) {'kind': l.kind, 'value': l.ctl.text.trim()}],
        });
      } on ApiException catch (e) {
        // الخادم بلا إضافة v2 بعد: حقول النواة حُفظت ولا نُفشل الحفظ
        if (e.statusCode != 404) rethrow;
      }
      final h = _handle.text.trim().toLowerCase();
      if (h.isNotEmpty && h != _originalHandle.toLowerCase() && (_handleCheck?.available ?? false)) {
        try {
          await api.patchMe({'nickname': h});
          final u = ref.read(appStateProvider).user;
          if (u != null) await ref.read(appStateProvider.notifier).updateUser(SessionUser(id: u.id, nickname: h, displayName: u.displayName, avatarUrl: u.avatarUrl));
        } catch (_) {
          if (mounted) toast(context, 'حُفظ الملف، لكن تغيير اسم المستخدم غير متاح حالياً');
        }
      }
      ref.invalidate(profileProvider);
      ref.invalidate(myProfileV2Provider);
      if (!mounted) return;
      // الرسالة قبل الإغلاق: بعد pop لا سياق لهذه الشاشة
      toast(context, 'حُفظ ملفك');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, e is ApiException && e.body?['error'] == 'bad-field' ? 'تحقق من الحقل: ${e.body?['field']}' : errText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// بطاقة اختيار نوع الحساب.
class _AccountCard extends StatelessWidget {
  final bool selected;
  final String title, subtitle;
  final VoidCallback onTap;
  const _AccountCard({super.key, required this.selected, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: selected ? Joy.primarySoft : Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? Joy.primary : Joy.line, width: selected ? 1.5 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Joy.primary : Joy.text))), if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: Joy.primary)]),
            Text(subtitle, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

/// بطاقة اختيار نمط التعريف (صوت/فيديو).
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ModeCard({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(color: selected ? Joy.primarySoft : Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? Joy.primary : Joy.line, width: selected ? 1.5 : 1)),
          child: Column(children: [
            Icon(icon, color: Joy.primary, size: 26),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text(subtitle, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5), textAlign: TextAlign.center),
          ]),
        ),
      );
}
