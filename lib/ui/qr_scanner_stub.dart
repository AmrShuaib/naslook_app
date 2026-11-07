import 'dart:typed_data';

import 'qr_scanner.dart';

/// خارج الويب لا معاينة حية في التطبيق (LiveCamera للويب فقط): الورقة تلتقط صورة بكاميرا النظام وتفكّها بـ zxing2.
bool get liveSupported => false;

QrCamera createQrCamera() => throw UnsupportedError('QrCamera is web-only');

Future<String?> decodeImageBytes(Uint8List bytes) => decodeQrEncoded(bytes);
