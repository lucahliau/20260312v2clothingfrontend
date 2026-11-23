import SwiftUI
import UIKit
import CoreText
import CoreGraphics

/// Launch hook: cancels notifications scheduled by older builds.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationsManager.cancelLegacyNotifications()
        return true
    }
}

@main
struct _0260312v2clothingfrontendApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authViewModel = AuthViewModel()

    init() {
        configureURLCache()
        registerMontserratFontIfNeeded()
        // Nav/tab bar appearance for the active theme (re-applied on switch via
        // ThemeStore). Must run after font registration so Montserrat resolves.
        Theme.current.applyUIKitAppearance()
        CrashReportService.shared.start()
        // Ship any analytics events left on disk from the previous run.
        AnalyticsManager.shared.startup()
    }

    private func configureURLCache() {
        let memory = 50 * 1024 * 1024
        let disk = 200 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "url_cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
        }
    }

    private func registerMontserratFontIfNeeded() {
        if UIFont(name: "Montserrat-Regular", size: 17) != nil {
            #if DEBUG
            print("[Montserrat] Font loaded via UIAppFonts")
            #endif
            return
        }

        let fontURL = Bundle.main.url(forResource: "Montserrat-Variable", withExtension: "ttf", subdirectory: nil)
            ?? Bundle.main.url(forResource: "Montserrat-Variable", withExtension: "ttf", subdirectory: "Fonts")
        #if DEBUG
        if fontURL != nil {
            print("[Montserrat] Font file: \(fontURL!.path)")
        } else {
            print("[Montserrat] Font file NOT in bundle")
        }
        #endif

        guard let url = fontURL,
              let fontData = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(fontData) else {
            #if DEBUG
            print("[Montserrat] Failed to create CGFont")
            #endif
            return
        }

        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            #if DEBUG
            print("[Montserrat] Registered via CTFontManager")
            #endif
        } else if let err = error?.takeUnretainedValue() {
            #if DEBUG
            print("[Montserrat] Registration failed: \(err)")
            #endif
        }
    }
}
