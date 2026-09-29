import SwiftUI

/// 첫 화면: 방 만들기 / 혼자 불멍.
struct LobbyView: View {
    @Environment(AppModel.self) private var appModel
    let isEligibleForGroupSession: Bool
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                )
                .symbolEffect(.breathe)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("불멍 라디오")
                    .font(.extraLargeTitle)
                Text("모닥불에 둘러앉아 함께 듣는 라디오")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                if isEligibleForGroupSession {
                    Button {
                        isCreating = true
                        Task {
                            await appModel.createRoom()
                            isCreating = false
                        }
                    } label: {
                        Label("방 만들기", systemImage: "shareplay")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .disabled(isCreating)
                    .accessibilityHint("SharePlay로 최대 8명이 함께하는 방을 만듭니다")
                } else {
                    // FaceTime 통화가 없으면 시스템 공유 시트로 초대(근처 공유·메시지 포함).
                    ShareLink(item: RadioActivity(),
                              preview: SharePreview("불멍 라디오", image: Image(systemName: "flame.fill"))) {
                        Label("초대해서 방 만들기", systemImage: "shareplay")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .accessibilityHint("SharePlay 초대를 보내 최대 8명이 함께하는 방을 만듭니다")
                }

                Button {
                    appModel.startSolo()
                } label: {
                    Label("혼자 불멍", systemImage: "person.fill")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
                .accessibilityHint("SharePlay 없이 모닥불 공간을 엽니다")
            }

            Text(isEligibleForGroupSession
                 ? "FaceTime 통화 중 · 바로 방을 만들 수 있어요"
                 : "FaceTime 통화가 없으면 초대 화면이 열립니다")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let status = appModel.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()

            Text("방장만 음악을 송출하고, 모두가 모닥불에 아이템을 던져 불 색을 바꿀 수 있어요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .padding()
    }
}
