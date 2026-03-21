import SwiftUI
import UIKit
import CoreText
import CoreGraphics

@main
struct _0260312v2clothingfrontendApp: App {
    @State private var authViewModel = AuthViewModel()

    init() {
        configureURLCache()
        registerMontserratFontIfNeeded()
        configureNavigationBarHeaders()
        configureTabBarAppearance()
    }

    private func configureURLCache() {
        let memory = 50 * 1024 * 1024
        let disk = 200 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "url_cache")
    }

    private func configureNavigationBarHeaders() {
        let titleLarge = UIFont.appDisplay(size: 34)
        let titleInline = UIFont.appDisplay(size: 17)
        let titleSmall = UIFont.appDisplay(size: 10)
        let titleColor = UIColor(Color.appOnHalftonePrimary)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [.font: titleLarge, .foregroundColor: titleColor]
        navAppearance.titleTextAttributes = [.font: titleInline, .foregroundColor: titleColor]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(Color.appAccent)
    }

    private func configureTabBarAppearance() {
        let tabFont = UIFont.appDisplay(size: 10)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: tabFont,
            .foregroundColor: UIColor(Color.appSecondaryText),
        ]
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: tabFont,
            .foregroundColor: UIColor(Color.appAccent),
        ]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(Color.appAccent)
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
