import Foundation
import RealityKit
import UIKit

/// 돌 원, 장작 티피, 숯, 불 트리거 볼륨 등 모닥불의 정적 구성.
enum CampfireBuilder {
    static let fireBaseHeight: Float = 0.16
    static let triggerRadius: Float = 0.5

    static func makeCampfire() -> Entity {
        let root = Entity()
        root.name = "campfire"

        var rng = SeededGenerator(seed: 0xCAFE_F00D)

        // 돌 12개
        var stone = PhysicallyBasedMaterial()
        stone.baseColor = .init(tint: UIColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1))
        stone.roughness = 0.95
        stone.metallic = 0.0
        let stoneMesh = MeshResource.generateSphere(radius: 0.09)
        for i in 0..<12 {
            let angle = Float(i) / 12 * 2 * .pi + Float(rng.nextUnit()) * 0.15
            let radius: Float = 0.55 + Float(rng.nextUnit()) * 0.05
            let entity = ModelEntity(mesh: stoneMesh, materials: [stone])
            entity.position = [radius * cos(angle), 0.05, radius * sin(angle)]
            entity.scale = [1.0 + Float(rng.nextUnit()) * 0.35, 0.6 + Float(rng.nextUnit()) * 0.2, 0.85 + Float(rng.nextUnit()) * 0.3]
            entity.orientation = simd_quatf(angle: Float(rng.nextUnit()) * .pi, axis: [0, 1, 0])
            root.addChild(entity)
        }

        // 재 바닥
        var ash = PhysicallyBasedMaterial()
        ash.baseColor = .init(tint: UIColor(red: 0.16, green: 0.14, blue: 0.13, alpha: 1))
        ash.roughness = 1.0
        let ashBed = ModelEntity(mesh: .generateCylinder(height: 0.03, radius: 0.5), materials: [ash])
        ashBed.position = [0, 0.015, 0]
        root.addChild(ashBed)

        // 장작 5개 티피
        var bark = PhysicallyBasedMaterial()
        bark.baseColor = .init(tint: UIColor(red: 0.33, green: 0.21, blue: 0.12, alpha: 1))
        bark.roughness = 0.9
        let logMesh = MeshResource.generateCylinder(height: 0.56, radius: 0.045)
        for i in 0..<5 {
            let angle = Float(i) / 5 * 2 * .pi + 0.3
            let base = SIMD3<Float>(0.24 * cos(angle), 0.045, 0.24 * sin(angle))
            let top = SIMD3<Float>(0.04 * cos(angle + 0.5), 0.50, 0.04 * sin(angle + 0.5))
            let log = ModelEntity(mesh: logMesh, materials: [bark])
            log.position = (base + top) / 2
            log.orientation = simd_quatf(from: [0, 1, 0], to: normalize(top - base))
            root.addChild(log)
        }
        // 바닥 가로 장작 2개
        for i in 0..<2 {
            let log = ModelEntity(mesh: .generateCylinder(height: 0.5, radius: 0.05), materials: [bark])
            let angle: Float = i == 0 ? 0.4 : 1.9
            log.position = [0, 0.06, 0]
            log.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) * simd_quatf(angle: angle, axis: [0, 0, 1])
            log.orientation = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            root.addChild(log)
        }

        // 숯: 자체 발광
        var charcoal = PhysicallyBasedMaterial()
        charcoal.baseColor = .init(tint: UIColor(red: 0.15, green: 0.05, blue: 0.02, alpha: 1))
        charcoal.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 1))
        charcoal.emissiveIntensity = 2.5
        charcoal.roughness = 0.8
        let charcoalMesh = MeshResource.generateSphere(radius: 0.06)
        for i in 0..<5 {
            let angle = Float(i) / 5 * 2 * .pi
            let entity = ModelEntity(mesh: charcoalMesh, materials: [charcoal])
            entity.name = "charcoal"
            entity.position = [0.12 * cos(angle), 0.09, 0.12 * sin(angle)]
            entity.scale = [1.2, 0.6, 1.0]
            root.addChild(entity)
        }

        return root
    }

    /// 불에 닿았는지 판단하는 트리거 볼륨.
    static func makeFireTrigger() -> Entity {
        let trigger = Entity()
        trigger.name = "fireTrigger"
        trigger.position = [0, 0.45, 0]
        trigger.components.set(CollisionComponent(shapes: [.generateSphere(radius: triggerRadius)], mode: .trigger))
        return trigger
    }
}
