import SwiftUI
import GroupActivities

/// 메인 윈도우 루트. 모드에 따라 로비/방 패널을 보여주고 이머시브 열기·닫기를 담당한다.
struct LobbyRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @StateObject private var groupStateObserver = GroupStateObserver()

    var body: some View {
        @Bindable var appModel = appModel
        Group {
            switch appModel.mode {
            case .idle:
                LobbyView(isEligibleForGroupSession: groupStateObserver.isEligibleForGroupSession)
            case .solo, .shared:
                RoomControlView()
            }
        }
        .task {
            await appModel.observeSessions()
        }
        .task {
            #if DEBUG
            // 시뮬레이터 검증용 런치 인자: autosolo(솔로 진입), autodemo(데모 재생), autothrow(6초 후 구리 조각 던지기)
            let arguments = CommandLine.arguments
            if arguments.contains("autosolo") {
                appModel.startSolo()
                if arguments.contains("autodemo") {
                    try? await Task.sleep(for: .seconds(3))
                    appModel.playDemo()
                }
                if arguments.contains("autothrow") {
                    try? await Task.sleep(for: .seconds(3))
                    appModel.enqueueThrow(.copper)
                }
            }
            #endif
        }
        .onChange(of: appModel.wantsImmersive) { _, wants in
            Task {
                if wants, !appModel.immersiveOpen {
                    switch await openImmersiveSpace(id: SceneID.campfire) {
                    case .opened:
                        appModel.immersiveOpen = true
                    case .userCancelled, .error:
                        appModel.wantsImmersive = false
                    @unknown default:
                        appModel.wantsImmersive = false
                    }
                } else if !wants, appModel.immersiveOpen {
                    await dismissImmersiveSpace()
                    appModel.immersiveOpen = false
                }
            }
        }
        .alert("함께 들어갈까요?", isPresented: $appModel.groupImmersiveSuggestion) {
            Button("스카이돔으로 이동") {
                appModel.wantsImmersive = true
            }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("다른 참가자가 모닥불 공간을 열었습니다.")
        }
    }
}
