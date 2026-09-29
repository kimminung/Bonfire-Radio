import SwiftUI
import UniformTypeIdentifiers

/// 방 안 컨트롤 패널. 방장/솔로에는 송출 컨트롤, 청취자에게는 안내를 보여준다.
struct RoomControlView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showFileImporter = false
    @State private var showEndConfirm = false

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack {
            Form {
                headerSection
                if appModel.canControlBroadcast {
                    musicSection
                    fireSection
                } else {
                    listenerSection
                }
                throwSection
                spaceSection
                if let status = appModel.statusMessage {
                    Section {
                        Text(status).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(appModel.mode == .solo ? "혼자 불멍" : "불멍 라디오")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showEndConfirm = true
                    } label: {
                        Label(appModel.isHost && appModel.mode == .shared ? "방송 끝내기" : "나가기", systemImage: "xmark.circle")
                    }
                }
            }
            .confirmationDialog(appModel.isHost && appModel.mode == .shared ? "모두의 방송을 끝낼까요?" : "공간을 나갈까요?",
                                isPresented: $showEndConfirm, titleVisibility: .visible) {
                Button(appModel.isHost && appModel.mode == .shared ? "방송 끝내기" : "나가기", role: .destructive) {
                    appModel.leaveRoom()
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    appModel.playHostFile(url: url)
                }
            }
        }
    }

    // MARK: 섹션

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                if appModel.canControlBroadcast {
                    OnAirBadge(isLive: appModel.roomState.nowPlaying?.isPlaying == true || appModel.mode == .shared)
                } else {
                    Image(systemName: "headphones")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.canControlBroadcast ? "당신이 방장입니다" : "\(hostName) 님의 방송")
                        .font(.headline)
                    Text(appModel.mode == .solo
                         ? "SharePlay 없이 혼자 즐기는 모드"
                         : "참가자 \(appModel.participantCount)/\(CampfireSpatialTemplate.seatCount)명")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                FlameChip(tint: appModel.roomState.tint)
            }
            .padding(.vertical, 4)
        }
    }

    private var musicSection: some View {
        @Bindable var appModel = appModel
        return Section("음원 · 방장만 송출") {
            if let nowPlaying = appModel.roomState.nowPlaying {
                HStack {
                    Image(systemName: nowPlaying.isPlaying ? "waveform" : "pause.circle")
                        .symbolEffect(.variableColor.iterative, isActive: nowPlaying.isPlaying)
                    VStack(alignment: .leading) {
                        Text(nowPlaying.title).lineLimit(1)
                        Text(nowPlaying.sourceLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(nowPlaying.isPlaying ? "일시정지" : "재생") {
                        appModel.togglePlayback()
                    }
                    .buttonStyle(.bordered)
                    Button("정지", role: .destructive) {
                        appModel.stopMusic()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("재생 중인 음원이 없습니다")
                    .foregroundStyle(.secondary)
            }

            Button {
                appModel.playDemo()
            } label: {
                Label("데모 트랙 재생 (Lo-fi)", systemImage: "music.quarternote.3")
            }

            HStack {
                TextField("스트림 URL (http://…)", text: $appModel.streamURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("재생") {
                    appModel.playStream()
                }
                .buttonStyle(.bordered)
                .disabled(appModel.streamURLText.isEmpty)
            }

            Button {
                showFileImporter = true
            } label: {
                Label("내 파일 재생 (이 기기만)", systemImage: "folder")
            }

            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: Binding(get: { Double(appModel.audio.volume) },
                                      set: { appModel.audio.volume = Float($0) }), in: 0...1)
                    .accessibilityLabel("볼륨")
            }

            if appModel.mode == .solo {
                Button {
                    Task { await appModel.toggleMic() }
                } label: {
                    Label(appModel.audio.micState == .on ? "목소리 반응 끄기" : "목소리 반응 켜기 (마이크)",
                          systemImage: appModel.audio.micState == .on ? "mic.fill" : "mic")
                }
                if case .unavailable(let reason) = appModel.audio.micState {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("목소리는 FaceTime 음성으로 전달됩니다. 청취자에게는 마이크를 꺼두도록 안내합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fireSection: some View {
        Section("모닥불") {
            HStack {
                Text("불 색")
                Spacer()
                Text(appModel.roomState.tint.displayName).foregroundStyle(.secondary)
                Button("초기화") {
                    appModel.resetTint()
                }
                .buttonStyle(.bordered)
                .disabled(appModel.roomState.tint == .default)
            }
            HStack {
                Image(systemName: "flame")
                Slider(value: Binding(get: { Double(appModel.roomState.intensity) },
                                      set: { appModel.setIntensity(Float($0)) }), in: 0.5...1.5)
                    .accessibilityLabel("불 세기")
            }
            Toggle("불꽃 깜빡임 줄이기", isOn: Binding(get: { appModel.roomState.reduceFlicker },
                                              set: { appModel.setReduceFlicker($0) }))
        }
    }

    private var listenerSection: some View {
        Section("청취자 모드") {
            if let nowPlaying = appModel.roomState.nowPlaying {
                HStack {
                    Image(systemName: nowPlaying.isPlaying ? "waveform" : "pause.circle")
                    VStack(alignment: .leading) {
                        Text(nowPlaying.title).lineLimit(1)
                        Text(nowPlaying.source == .hostFile ? "방장 기기에서만 재생되는 파일입니다" : nowPlaying.sourceLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("방장이 아직 음악을 틀지 않았어요").foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: Binding(get: { Double(appModel.audio.volume) },
                                      set: { appModel.audio.volume = Float($0) }), in: 0...1)
                    .accessibilityLabel("볼륨")
            }
            Label("이 방에서는 방장만 마이크와 음악을 송출합니다. FaceTime 마이크를 꺼두면 더 좋아요.", systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var throwSection: some View {
        Section("모닥불에 던지기") {
            Text("앞의 바구니에서 물건을 잡아 모닥불에 던져보세요. 불 색이 바뀝니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ThrowableKind.allCases, id: \.self) { kind in
                        Button {
                            appModel.enqueueThrow(kind)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: kind.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(Color(kind.tint.palette.glow))
                                Text(kind.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 84, height: 70)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.immersiveOpen)
                        .accessibilityLabel("\(kind.name) 던지기, \(kind.tint.displayName)")
                    }
                }
            }
            if let last = appModel.lastLandedKind {
                Text("마지막으로 \(last.name)을(를) 던져 \(last.tint.displayName)이 되었어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var spaceSection: some View {
        Section("공간") {
            Button {
                appModel.wantsImmersive.toggle()
            } label: {
                Label(appModel.immersiveOpen ? "스카이돔 닫기" : "스카이돔 열기",
                      systemImage: appModel.immersiveOpen ? "moon.zzz" : "moon.stars")
            }
            Text("몰입도는 Digital Crown으로 조절할 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hostName: String {
        appModel.roomState.hostDisplayName.isEmpty ? "방장" : appModel.roomState.hostDisplayName
    }
}

// MARK: - 보조 뷰

private struct OnAirBadge: View {
    let isLive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? .red : .gray)
                .frame(width: 10, height: 10)
                .symbolEffect(.pulse, isActive: isLive)
            Text("ON AIR")
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.red.opacity(isLive ? 0.18 : 0.06), in: Capsule())
        .accessibilityLabel(isLive ? "방송 중" : "대기 중")
    }
}

private struct FlameChip: View {
    let tint: FlameTint

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [Color(tint.palette.core), Color(tint.palette.outerEnd)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: 18)
            Text(tint.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("현재 불 색 \(tint.displayName)")
    }
}

extension Color {
    init(_ color: FlameColor) {
        self.init(red: Double(color.r), green: Double(color.g), blue: Double(color.b), opacity: Double(color.a))
    }
}
