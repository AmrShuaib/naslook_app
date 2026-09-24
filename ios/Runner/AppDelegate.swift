import Flutter
import UIKit

// دورة حياة المشاهد (UIScene) كما في قالب Flutter 3.47: أبل تشترطها للتطبيقات المبنية بأحدث أدوات Xcode،
// والمحرك يُنشأ ضمنياً فتُسجَّل الإضافات عند تهيئته.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
