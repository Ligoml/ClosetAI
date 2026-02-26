import SwiftUI

struct ContentView: View {
    @StateObject private var wardrobeVM = WardrobeViewModel()
    @StateObject private var outfitVM = OutfitViewModel()

    var body: some View {
        TabView {
            WardrobeView()
                .tabItem {
                    Label("衣橱", systemImage: "tshirt")
                }
                .environmentObject(wardrobeVM)

            OutfitView()
                .tabItem {
                    Label("穿搭", systemImage: "sparkles")
                }
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .environmentObject(wardrobeVM)
        }
        .accentColor(AppColors.accent)
    }
}
