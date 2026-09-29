import SwiftUI

/// 모닥불 위에 떠 있는 현재 곡 라벨.
struct NowPlayingLabel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appModel.roomState.nowPlaying?.isPlaying == true ? "music.note" : "moon.stars")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.roomState.nowPlaying?.title ?? "불멍 라디오")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
        .opacity(appModel.roomState.nowPlaying == nil ? 0.6 : 1)
    }

    private var subtitle: String {
        if appModel.mode == .solo { return "혼자 불멍" }
        let host = appModel.roomState.hostDisplayName.isEmpty ? "방장" : appModel.roomState.hostDisplayName
        return "\(host) · \(appModel.participantCount)/\(CampfireSpatialTemplate.seatCount)명"
    }
}
