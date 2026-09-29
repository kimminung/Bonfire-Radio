import SwiftUI
import RealityKit

/// 스카이돔 + 모닥불 + 던지기 아이템으로 구성된 이머시브 공간.
struct CampfireImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scene = CampfireScene()

    var body: some View {
        RealityView { content in
            await scene.build(in: content, appModel: appModel)
        } update: { _ in
            scene.applyRoomState(appModel.roomState)
        }
        .onAppear {
            appModel.immersiveOpen = true
        }
        .onDisappear {
            appModel.immersiveOpen = false
            appModel.wantsImmersive = false
        }
    }
}

/// RealityView 수명과 함께 사는 씬 상태.
@Observable
final class CampfireScene {
    let root = Entity()
    let fire = FireVisualizer()
    let spawner = ThrowableSpawner()
    private var trigger = Entity()
    private var subscriptions: [EventSubscription] = []
    private weak var appModel: AppModel?
    private var elapsed: Double = 0
    private var sinceTick: Double = 0
    private var lastTint: FlameTint = .wood
    private var built = false

    func build(in content: RealityViewContent, appModel: AppModel) async {
        guard !built else { return }
        built = true
        self.appModel = appModel

        root.name = "campfireRoot"
        // 솔로 모드: 사용자 발 아래가 원점이므로 씬을 2.4m 앞으로 밀어 방장 좌석에 앉은 것처럼 배치.
        // SharePlay: 공유 좌표 원점(=모닥불)을 그대로 사용.
        let isShared = appModel.mode == .shared
        root.position = isShared ? .zero : SIMD3<Float>(0, 0, -Float(CampfireSpatialTemplate.radius))

        if let sky = try? await SkyDomeBuilder.makeSkyDome() {
            root.addChild(sky)
        }
        root.addChild(SkyDomeBuilder.makeGround())
        root.addChild(CampfireBuilder.makeCampfire())

        fire.root.position = [0, CampfireBuilder.fireBaseHeight, 0]
        root.addChild(fire.root)

        trigger = CampfireBuilder.makeFireTrigger()
        root.addChild(trigger)

        // 바구니: 로컬 참가자 좌석에서 모닥불 방향으로 0.6m 앞.
        let seat = appModel.session?.localSeatPosition ?? CampfireSpatialTemplate.seatPosition(index: 0)
        let seatFlat = SIMD3<Float>(seat.x, 0, seat.z)
        let seatDistance: Float = length(seatFlat)
        let toward: SIMD3<Float> = seatDistance > 0.01 ? normalize(seatFlat) : SIMD3<Float>(0, 0, 1)
        let trayDistance: Float = max(seatDistance, 1.2) - 0.6
        let trayPosition: SIMD3<Float> = toward * trayDistance + SIMD3<Float>(0, 0.75, 0)
        spawner.place(at: trayPosition, facing: [0, 0.75, 0])
        spawner.onLanded = { [weak appModel] kind in
            appModel?.throwLanded(kind: kind)
        }
        root.addChild(spawner.root)
        root.addChild(spawner.thrownRoot)

        // 모닥불 위 Now Playing 라벨: SwiftUI 뷰를 컴포넌트로 직접 부착(visionOS 26+).
        let label = Entity()
        label.name = "nowPlayingLabel"
        label.components.set(ViewAttachmentComponent(rootView: NowPlayingLabel().environment(appModel)))
        label.components.set(BillboardComponent())
        label.position = [0, 1.75, 0]
        root.addChild(label)

        content.add(root)

        subscriptions.append(content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(deltaTime: event.deltaTime)
        })
        subscriptions.append(content.subscribe(to: CollisionEvents.Began.self, on: trigger) { [weak self] event in
            guard let self else { return }
            let other = event.entityA == trigger ? event.entityB : event.entityA
            spawner.handleFireContact(other)
        })
        subscriptions.append(content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { [weak self] event in
            self?.spawner.handleTransformUpdate(event.entity)
        })
        subscriptions.append(content.subscribe(to: ManipulationEvents.WillRelease.self) { [weak self] event in
            self?.spawner.handleRelease(event.entity)
        })

        applyRoomState(appModel.roomState)
        fire.setTint(appModel.roomState.tint, animated: false)
        lastTint = appModel.roomState.tint
    }

    func applyRoomState(_ state: RoomState) {
        if state.tint != lastTint {
            lastTint = state.tint
            fire.setTint(state.tint, animated: true)
        }
    }

    private func tick(deltaTime: TimeInterval) {
        elapsed += deltaTime
        sinceTick += deltaTime
        spawner.update(now: elapsed)

        guard let appModel else { return }

        // 패널 폴백 던지기
        if !appModel.throwQueue.isEmpty {
            let kinds = appModel.throwQueue
            appModel.throwQueue.removeAll()
            let firePosition = trigger.position(relativeTo: nil)
            for kind in kinds {
                spawner.launchFallback(kind: kind, fireWorldPosition: firePosition)
            }
        }
        // 다른 참가자의 던지기: 버스트만 재현
        if !appModel.remoteThrowBursts.isEmpty {
            appModel.remoteThrowBursts.removeAll()
        }

        // 30Hz 갱신
        guard sinceTick >= 1.0 / 30.0 else { return }
        let dt = Float(sinceTick)
        sinceTick = 0
        let levels = appModel.audio.currentLevels()
        fire.update(deltaTime: dt,
                    levels: levels,
                    intensity: appModel.roomState.intensity,
                    reduceFlicker: appModel.roomState.reduceFlicker)
    }
}
