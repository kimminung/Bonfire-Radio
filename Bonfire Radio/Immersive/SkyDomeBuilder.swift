import Foundation
import CoreGraphics
import RealityKit
import UIKit

/// 절차적 밤하늘 스카이돔. 텍스처는 CoreGraphics로 생성한다(에셋 불필요).
enum SkyDomeBuilder {
    static let radius: Float = 60

    static func makeSkyDome() async throws -> Entity {
        let image = await Task.detached(priority: .userInitiated) {
            Self.renderSkyImage(width: 2048, height: 1024)
        }.value
        let texture = try await TextureResource(image: image, withName: "nightSky", options: .init(semantic: .color))
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .front
        let dome = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        dome.name = "skyDome"
        return dome
    }

    /// 어두운 지면. 돔의 아래 반구를 완전히 가려 텍스처 방향과 무관하게 지평선을 만든다.
    static func makeGround() -> Entity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.10, green: 0.085, blue: 0.07, alpha: 1))
        material.roughness = 1.0
        material.metallic = 0.0
        let ground = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: radius - 1), materials: [material])
        ground.name = "ground"
        ground.position = [0, -0.01, 0]
        ground.components.set(CollisionComponent(shapes: [.generateBox(size: [radius * 2, 0.02, radius * 2])]))
        ground.components.set(PhysicsBodyComponent(shapes: [.generateBox(size: [radius * 2, 0.02, radius * 2])],
                                                   mass: 0,
                                                   material: .generate(staticFriction: 0.9, dynamicFriction: 0.8, restitution: 0.1),
                                                   mode: .static))
        return ground
    }

    // MARK: 텍스처

    nonisolated private static func renderSkyImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        // 세로 그라데이션: 천정(짙은 남색) → 지평선(따뜻한 잔광) → 아래(어둠)
        let colors = [
            CGColor(red: 0.010, green: 0.015, blue: 0.055, alpha: 1),
            CGColor(red: 0.030, green: 0.040, blue: 0.110, alpha: 1),
            CGColor(red: 0.090, green: 0.075, blue: 0.150, alpha: 1),
            CGColor(red: 0.180, green: 0.110, blue: 0.130, alpha: 1),
            CGColor(red: 0.040, green: 0.030, blue: 0.035, alpha: 1),
            CGColor(red: 0.005, green: 0.005, blue: 0.010, alpha: 1)
        ]
        let locations: [CGFloat] = [1.0, 0.80, 0.62, 0.52, 0.47, 0.0]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(height)), options: [])

        // 은하수: 완만한 사인 곡선을 따라 흐린 점들을 뿌린다.
        var rng = SeededGenerator(seed: 0x5EED_1234)
        let horizon = CGFloat(height) * 0.52
        for _ in 0..<2600 {
            let x = CGFloat(rng.nextUnit()) * CGFloat(width)
            let bandCenter = horizon + CGFloat(height) * (0.22 + 0.10 * sin(x / CGFloat(width) * 2 * .pi + 0.6))
            let spread = CGFloat(height) * 0.06
            let y = bandCenter + CGFloat(rng.nextGaussian()) * spread
            guard y > horizon else { continue }
            let alpha = 0.04 + 0.08 * CGFloat(rng.nextUnit())
            let size = 2.0 + 5.0 * CGFloat(rng.nextUnit())
            context.setFillColor(CGColor(red: 0.75, green: 0.78, blue: 0.95, alpha: alpha))
            context.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        }

        // 별: 위쪽 반구에만.
        for _ in 0..<1800 {
            let x = CGFloat(rng.nextUnit()) * CGFloat(width)
            let y = horizon + CGFloat(rng.nextUnit()) * (CGFloat(height) - horizon)
            let brightness = 0.35 + 0.65 * CGFloat(rng.nextUnit()) * CGFloat(rng.nextUnit())
            let size = 1.0 + 2.2 * CGFloat(rng.nextUnit()) * brightness
            let warm = rng.nextUnit() < 0.25
            let color = warm
                ? CGColor(red: 1.0, green: 0.92, blue: 0.80, alpha: brightness)
                : CGColor(red: 0.85, green: 0.90, blue: 1.0, alpha: brightness)
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
            if brightness > 0.85 {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
                let halo = size * 3
                context.fillEllipse(in: CGRect(x: x - halo / 2, y: y - halo / 2, width: halo, height: halo))
            }
        }
        return context.makeImage()!
    }
}

/// 재현 가능한 텍스처를 위한 간단한 LCG.
nonisolated struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func nextGaussian() -> Double {
        let u1 = max(1e-9, nextUnit())
        let u2 = nextUnit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
