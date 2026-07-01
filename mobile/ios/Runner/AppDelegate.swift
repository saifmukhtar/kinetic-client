import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let attestationChannel = FlutterMethodChannel(name: "dev.saifmukhtar.kinetic/attestation",
                                                  binaryMessenger: controller.binaryMessenger)
    
    attestationChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "verifyDevice" {
        // Basic implementation for iOS: Emulators get BASIC, physical devices get STRONG
        #if targetEnvironment(simulator)
        result("MEETS_BASIC_INTEGRITY")
        #else
        // In a real production app, use DeviceCheck or AppAttest here
        result("MEETS_STRONG_INTEGRITY")
        #endif
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
