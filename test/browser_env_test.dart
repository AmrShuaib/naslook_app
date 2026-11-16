import 'package:flutter_test/flutter_test.dart';
import 'package:naslook/core/media/browser_env.dart';
import 'package:naslook/core/media/permissions.dart';

const _safari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

void main() {
  test('the browser environment decides which microphone steps are shown', () {
    expect(classifyBrowser(_safari, standalone: false), BrowserHost.iosSafari);
    expect(classifyBrowser(_safari, standalone: true), BrowserHost.iosStandalone);
    expect(classifyBrowser(_safari.replaceFirst('Version/18.0', 'CriOS/130.0'), standalone: false), BrowserHost.iosOther);
    expect(classifyBrowser('$_safari Instagram 350.0', standalone: false), BrowserHost.inApp);
    expect(classifyBrowser('Mozilla/5.0 (Linux; Android 14) Chrome/130.0 Mobile Safari/537.36', standalone: true), BrowserHost.other);
    expect(classifyBrowser('', standalone: false), BrowserHost.other);
    for (final h in BrowserHost.values) {
      expect(micDeniedHelp(h), isNotEmpty);
      expect(micDeniedTitle(h), isNotEmpty);
    }
    expect(micDeniedHelp(BrowserHost.inApp), contains('Safari'));
  });

  test('raw browser microphone errors become Arabic ones', () {
    const raw = 'NotAllowedError: The request is not allowed by the user agent or the platform in the current context, possibly because the user denied permission.';
    expect(mapMicError(raw), isA<MediaPermissionDenied>().having((e) => e.what, 'what', 'mic'));
    expect('${mapMicError('NotFoundError: Requested device not found')}', contains('ميكروفون'));
    expect('${mapMicError('NotReadableError: Could not start audio source')}', contains('مشغول'));
    final other = StateError('x');
    expect(mapMicError(other), same(other));
  });
}
