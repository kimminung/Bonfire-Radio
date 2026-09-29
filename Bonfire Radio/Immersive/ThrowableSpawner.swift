import Foundation
import RealityKit
import UIKit

/// 던질 수 있는 아이템에 붙는 컴포넌트.
nonisolated struct ThrowableComponent: Component, Sendable {
    var kind: ThrowableKind
    var slot: Int
    var releasedAt: Double?
}

/// 참가자 앞 바구니에 아이템을 배치하고, 잡기/던지기/충돌/리스폰을 처리한다.
final class ThrowableSpawner {
    /// 바구니(참가자 앞) 루트.
    let root = Entity()
    /// 던져진 아이템이 사는 컨테이너. 씬 루트(원점 = 모닥불) 바로 아래에 둔다.
    let thrownRoot = Entity()
    private let tray = Entity()
    private var slots: [Entity?] = [nil, nil, nil]
    private var respawnAt: [Double?] = [nil, nil, nil]
    private var nextKindIndex = 0
    private var samples: [Entity.ID: [(time: Double, position: SIMD3<Float>)]] = [:]
    private var now: Double = 0

    /// 아이템이 불에 닿았을 때 호출.
    var onLanded: ((ThrowableKind) -> Void)?

    private let slotOffsets: [SIMD3<Float>] = [[-0.12, 0.05, 0], [0, 0.05, -0.04], [0.12, 0.05, 0]]

    init() {
        root.name = "throwables"
        thrownRoot.name = "thrownItems"
        var trayMaterial = PhysicallyBasedMaterial()
        trayMaterial.baseColor = .init(tint: UIColor(red: 0.28, green: 0.20, blue: 0.14, alpha: 1))
        trayMaterial.roughness = 0.8
        let trayModel = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.2), materials: [trayMaterial])
        trayModel.components.set(CollisionComponent(shapes: [.generateBox(size: [0.4, 0.02, 0.4])]))
        trayModel.components.set(PhysicsBodyComponent(shapes: [.generateBox(size: [0.4, 0.02, 0.4])], mass: 0, mode: .static))
        tray.addChild(trayModel)
        root.addChild(tray)
        for slot in 0..<slots.count {
            spawn(slot: slot)
        }
    }

    /// 바구니 위치(참가자 정면 0.6m, 높이 0.75m).
    func place(at position: SIMD3<Float>, facing target: SIMD3<Float>) {
        root.position = position
        let direction = target - position
        let flat = SIMD3<Float>(direction.x, 0, direction.z)
        if length(flat) > 0.001 {
            root.orientation = simd_quatf(from: [0, 0, -1], to: normalize(flat))
        }
    }

    // MARK: 아이템 생성

    private func spawn(slot: Int) {
        let kind = ThrowableKind.allCases[nextKindIndex % ThrowableKind.allCases.count]
        nextKindIndex += 1
        let item = makeItem(kind: kind, slot: slot)
        item.position = slotOffsets[slot]
        tray.addChild(item)
        slots[slot] = item
        respawnAt[slot] = nil
    }

    private func makeItem(kind: ThrowableKind, slot: Int) -> Entity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(kind.bodyColor))
        material.metallic = kind.isMetallic ? 0.9 : 0.0
        material.roughness = kind.isMetallic ? 0.35 : 0.7
        if kind == .stardust {
            material.emissiveColor = .init(color: UIColor(kind.bodyColor))
            material.emissiveIntensity = 1.5
        }

        let mesh: MeshResource
        let shape: ShapeResource
        switch kind.shape {
        case .sphere:
            mesh = .generateSphere(radius: 0.035)
            shape = .generateSphere(radius: 0.035)
        case .cube:
            mesh = .generateBox(size: 0.055, cornerRadius: 0.008)
            shape = .generateBox(size: [0.055, 0.055, 0.055])
        case .cylinder:
            mesh = .generateCylinder(height: 0.07, radius: 0.022)
            shape = .generateCapsule(height: 0.07, radius: 0.022)
        case .crystal:
            mesh = .generateBox(size: [0.035, 0.07, 0.035], cornerRadius: 0.004)
            shape = .generateBox(size: [0.035, 0.07, 0.035])
        }

        let item = ModelEntity(mesh: mesh, materials: [material])
        item.name = "item.\(kind.rawValue)"
        if kind.shape == .crystal {
            item.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0]) * simd_quatf(angle: 0.3, axis: [1, 0, 0])
        }

        ManipulationComponent.configureEntity(item, collisionShapes: [shape])
        var manipulation = item.components[ManipulationComponent.self] ?? ManipulationComponent()
        manipulation.releaseBehavior = .stay
        item.components.set(manipulation)

        item.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.2,
            material: .generate(staticFriction: 0.8, dynamicFriction: 0.6, restitution: 0.25),
            mode: .kinematic
        ))
        item.components.set(ThrowableComponent(kind: kind, slot: slot))
        return item
    }

    // MARK: 이벤트

    func handleTransformUpdate(_ entity: Entity) {
        guard entity.components.has(ThrowableComponent.self) else { return }
        var history = samples[entity.id] ?? []
        history.append((now, entity.position(relativeTo: nil)))
        if history.count > 12 { history.removeFirst(history.count - 12) }
        samples[entity.id] = history
    }

    func handleRelease(_ entity: Entity) {
        guard var throwable = entity.components[ThrowableComponent.self] else { return }
        let history = samples[entity.id] ?? []
        samples[entity.id] = nil

        var velocity = SIMD3<Float>(0, 0, 0)
        if let last = history.last {
            // 최근 ~80ms 구간의 평균 속도
            let recent = history.filter { last.time - $0.time <= 0.09 }
            if let first = recent.first, last.time - first.time > 0.005 {
                velocity = (last.position - first.position) / Float(last.time - first.time)
            }
        }
        let speed = length(velocity)
        if speed > 8 { velocity = velocity / speed * 8 }
        velocity *= 1.15

        // 바구니(회전된 루트)에서 씬 좌표계 컨테이너로 옮긴다.
        entity.setParent(thrownRoot, preservingWorldTransform: true)

        var body = entity.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        body.mode = .dynamic
        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent(linearVelocity: velocity,
                                                     angularVelocity: [Float.random(in: -3...3), Float.random(in: -3...3), Float.random(in: -3...3)]))
        throwable.releasedAt = now
        entity.components.set(throwable)
        if slots[throwable.slot] === entity {
            slots[throwable.slot] = nil
            respawnAt[throwable.slot] = now + 2.0
        }
    }

    /// 불 트리거에 들어온 엔티티 처리. 성공 시 kind 반환.
    @discardableResult
    func handleFireContact(_ entity: Entity) -> ThrowableKind? {
        guard let throwable = entity.components[ThrowableComponent.self], throwable.releasedAt != nil else { return nil }
        entity.removeFromParent()
        onLanded?(throwable.kind)
        return throwable.kind
    }

    /// 패널 "던지기" 폴백: 바구니에서 불을 향해 포물선으로 발사.
    func launchFallback(kind: ThrowableKind, fireWorldPosition: SIMD3<Float>) {
        let item = makeItem(kind: kind, slot: -1)
        let start = root.position(relativeTo: nil) + [0, 0.25, 0]
        thrownRoot.addChild(item)
        item.setPosition(start, relativeTo: nil)
        var body = item.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        body.mode = .dynamic
        item.components.set(body)
        // 간단한 포물선: 수평 거리 d, 비행 시간 t → vx = d/t, vy = (h + 0.5 g t^2)/t
        let target = fireWorldPosition + [0, 0.45, 0]
        let delta = target - start
        let flat = SIMD3<Float>(delta.x, 0, delta.z)
        let distance = length(flat)
        let flightTime: Float = max(0.6, distance / 3.0)
        let horizontal = distance > 0.001 ? normalize(flat) * (distance / flightTime) : .zero
        let vy = (delta.y + 0.5 * 9.81 * flightTime * flightTime) / flightTime
        item.components.set(PhysicsMotionComponent(linearVelocity: horizontal + [0, vy, 0], angularVelocity: [2, 1, 0]))
        var throwable = item.components[ThrowableComponent.self]!
        throwable.releasedAt = now
        item.components.set(throwable)
    }

    // MARK: 틱

    func update(now: Double) {
        self.now = now
        for slot in 0..<slots.count {
            if slots[slot] == nil, let at = respawnAt[slot], now >= at {
                spawn(slot: slot)
            }
        }
        // 던져진 뒤 오래 남은 아이템 정리
        for child in Array(thrownRoot.children) {
            guard let throwable = child.components[ThrowableComponent.self], let released = throwable.releasedAt else { continue }
            if now - released > 8 || child.position(relativeTo: nil).y < -2 {
                child.removeFromParent()
            }
        }
    }
}
