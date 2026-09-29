import SwiftUI
import RealityKit

/// 불멍 라디오 — 모닥불에 둘러앉아 함께 듣는 visionOS SharePlay 라디오.
@main
struct BonfireRadioApp: App {
    @State private var appModel = AppModel()

    init() {
        ThrowableComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: SceneID.lobby) {
            LobbyRootView()
                .environment(appModel)
        }
        .defaultSize(width: 520, height: 640)

        ImmersiveSpace(id: SceneID.campfire) {
            CampfireImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: Bindable(appModel).immersionStyle, in: .progressive, .full)
    }
}

enum SceneID {
    static let lobby = "lobby"
    static let campfire = "campfire"
}
