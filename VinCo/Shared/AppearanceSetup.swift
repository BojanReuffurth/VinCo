import UIKit; import SwiftUI
enum AppearanceSetup {
    static func apply(accent: String = "#E8A87C") {
        let ac = UIColor(Color(hex: accent))

        // Dynamic colors that flip with trait collection
        let bg1Text = UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(Color(hex: "#111111")) : UIColor(Color(hex: "#FFFFFF"))
        }
        let titleColor = UIColor { t in
            t.userInterfaceStyle == .dark ? .white : UIColor(Color(hex: "#0D0D0D"))
        }
        let monoFont17 = UIFont(name: "Courier New", size: 17) ?? .monospacedSystemFont(ofSize: 17, weight: .semibold)
        let monoFont32 = UIFont(name: "Courier New", size: 32) ?? .monospacedSystemFont(ofSize: 32, weight: .bold)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor    = bg1Text   // resolved per trait
        nav.shadowColor        = UIColor(Theme.divide)
        nav.titleTextAttributes      = [.foregroundColor: titleColor, .font: monoFont17]
        nav.largeTitleTextAttributes = [.foregroundColor: titleColor, .font: monoFont32]
        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().compactAppearance    = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor            = ac

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bg1)
        tab.shadowColor     = UIColor(Theme.divide)
        for style in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            style.selected.iconColor = ac
            style.selected.titleTextAttributes = [.foregroundColor: ac]
            style.normal.iconColor   = UIColor(Theme.textS)
            style.normal.titleTextAttributes   = [.foregroundColor: UIColor(Theme.textS)]
        }
        UITabBar.appearance().standardAppearance  = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITableView.appearance().backgroundColor  = UIColor(Theme.bg0)
        UITableViewCell.appearance().backgroundColor = UIColor(Theme.bg1)
        UITableView.appearance().separatorColor   = UIColor(Theme.divide)
    }
}
