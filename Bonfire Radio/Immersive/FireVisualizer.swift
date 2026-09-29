import Foundation
import RealityKit
import UIKit

extension UIColor {
    convenience init(_ color: FlameColor) {
        self.init(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: CGFloat(color.a))
    }
}

/// 다층 파티클 모닥불 비주얼라이저. 오디오 레벨과 불 색 팔레트로 매 틱 파라미터를 갱신한다.
final class FireVisualizer {
    typealias Emitter = ParticleEmitterComponent.ParticleEmitter

    let root = Entity()
    private let core = Entity()
    private let outer = Entity()
    private let embers = Entity()
    private let smoke = Entity()
    private let halo = Entity()
    private let light = Entity()

    private var coreBase = ParticleEmitterComponent()
    private var outerBase = ParticleEmitterComponent()
    private var embersBase = ParticleEmitterComponent()
    private var smokeBase = ParticleEmitterComponent()
    private var haloBase = ParticleEmitterComponent()

    private var currentTint: FlameTint = .wood
    private var fromPalette = FlameTint.wood.palette
    private var toPalette = FlameTint.wood.palette
    private var blend: Float = 1
    private let blendDuration: Float = 1.5
    private var time: Float = 0
    private var flash: Float = 0
    private var burstEntities: [(Entity, Float)] = []

    private(set) var palette = FlameTint.wood.palette

    init() {
        root.name = "fire"
        configureEmitters()
        core.position = [0, 0, 0]
        outer.position = [0, 0.02, 0]
        embers.position = [0, 0.15, 0]
        smoke.position = [0, 0.55, 0]
        halo.position = [0, 0.25, 0]
        light.position = [0, 0.45, 0]
        light.components.set(PointLightComponent(color: UIColor(palette.glow), intensity: 900, attenuationRadius: 8))
        for child in [core, outer, embers, smoke, halo, light] {
            root.addChild(child)
        }
        applyPalette(palette)
    }

    // MARK: 구성

    private func configureEmitters() {
        // 코어 불꽃: 밝고 빠른 중심 화염
        coreBase.emitterShape = .cone
        coreBase.emitterShapeSize = [0.18, 0.05, 0.18]
        coreBase.birthLocation = .volume
        coreBase.birthDirection = .local
        coreBase.emissionDirection = [0, 1, 0]
        coreBase.speed = 0.9
        coreBase.speedVariation = 0.3
        coreBase.mainEmitter.birthRate = 240
        coreBase.mainEmitter.birthRateVariation = 40
        coreBase.mainEmitter.lifeSpan = 0.6
        coreBase.mainEmitter.lifeSpanVariation = 0.25
        coreBase.mainEmitter.size = 0.085
        coreBase.mainEmitter.sizeVariation = 0.03
        coreBase.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.25
        coreBase.mainEmitter.opacityCurve = .quickFadeInOut
        coreBase.mainEmitter.blendMode = .additive
        coreBase.mainEmitter.acceleration = [0, 1.6, 0]
        coreBase.mainEmitter.dampingFactor = 0.4
        coreBase.mainEmitter.noiseStrength = 0.9
        coreBase.mainEmitter.noiseScale = 2.2
        coreBase.mainEmitter.noiseAnimationSpeed = 1.5
        coreBase.mainEmitter.angularSpeed = 1.0
        coreBase.mainEmitter.angularSpeedVariation = 1.0
        coreBase.mainEmitter.stretchFactor = 1.4
        coreBase.mainEmitter.isLightingEnabled = false

        // 외곽 불꽃: 크고 느린 혀 모양
        outerBase.emitterShape = .cone
        outerBase.emitterShapeSize = [0.28, 0.06, 0.28]
        outerBase.birthLocation = .volume
        outerBase.birthDirection = .local
        outerBase.emissionDirection = [0, 1, 0]
        outerBase.speed = 0.55
        outerBase.speedVariation = 0.25
        outerBase.mainEmitter.birthRate = 90
        outerBase.mainEmitter.birthRateVariation = 20
        outerBase.mainEmitter.lifeSpan = 1.0
        outerBase.mainEmitter.lifeSpanVariation = 0.3
        outerBase.mainEmitter.size = 0.16
        outerBase.mainEmitter.sizeVariation = 0.05
        outerBase.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.3
        outerBase.mainEmitter.opacityCurve = .quickFadeInOut
        outerBase.mainEmitter.blendMode = .additive
        outerBase.mainEmitter.acceleration = [0, 1.0, 0]
        outerBase.mainEmitter.dampingFactor = 0.5
        outerBase.mainEmitter.noiseStrength = 1.4
        outerBase.mainEmitter.noiseScale = 1.6
        outerBase.mainEmitter.noiseAnimationSpeed = 1.2
        outerBase.mainEmitter.angularSpeed = 0.6
        outerBase.mainEmitter.angularSpeedVariation = 0.8
        outerBase.mainEmitter.stretchFactor = 1.6
        outerBase.mainEmitter.isLightingEnabled = false

        // 불씨
        embersBase.emitterShape = .sphere
        embersBase.emitterShapeSize = [0.2, 0.1, 0.2]
        embersBase.birthLocation = .volume
        embersBase.birthDirection = .local
        embersBase.emissionDirection = [0, 1, 0]
        embersBase.speed = 0.6
        embersBase.speedVariation = 0.4
        embersBase.mainEmitter.birthRate = 40
        embersBase.mainEmitter.lifeSpan = 2.5
        embersBase.mainEmitter.lifeSpanVariation = 1.2
        embersBase.mainEmitter.size = 0.012
        embersBase.mainEmitter.sizeVariation = 0.006
        embersBase.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        embersBase.mainEmitter.opacityCurve = .linearFadeOut
        embersBase.mainEmitter.blendMode = .additive
        embersBase.mainEmitter.acceleration = [0, 0.5, 0]
        embersBase.mainEmitter.dampingFactor = 0.6
        embersBase.mainEmitter.noiseStrength = 1.0
        embersBase.mainEmitter.noiseScale = 1.0
        embersBase.mainEmitter.noiseAnimationSpeed = 0.8
        embersBase.mainEmitter.isLightingEnabled = false

        // 연기
        smokeBase.emitterShape = .sphere
        smokeBase.emitterShapeSize = [0.2, 0.1, 0.2]
        smokeBase.birthLocation = .volume
        smokeBase.birthDirection = .local
        smokeBase.emissionDirection = [0, 1, 0]
        smokeBase.speed = 0.35
        smokeBase.speedVariation = 0.1
        smokeBase.mainEmitter.birthRate = 14
        smokeBase.mainEmitter.lifeSpan = 4.5
        smokeBase.mainEmitter.lifeSpanVariation = 1.0
        smokeBase.mainEmitter.size = 0.28
        smokeBase.mainEmitter.sizeVariation = 0.1
        smokeBase.mainEmitter.sizeMultiplierAtEndOfLifespan = 2.8
        smokeBase.mainEmitter.opacityCurve = .gradualFadeInOut
        smokeBase.mainEmitter.blendMode = .alpha
        smokeBase.mainEmitter.acceleration = [0.15, 0.25, 0.05]
        smokeBase.mainEmitter.dampingFactor = 0.3
        smokeBase.mainEmitter.noiseStrength = 0.5
        smokeBase.mainEmitter.noiseScale = 0.8
        smokeBase.mainEmitter.noiseAnimationSpeed = 0.3
        smokeBase.mainEmitter.angularSpeed = 0.3
        smokeBase.mainEmitter.isLightingEnabled = false

        // 광륜(열기 대체)
        haloBase.emitterShape = .sphere
        haloBase.emitterShapeSize = [0.05, 0.05, 0.05]
        haloBase.birthLocation = .volume
        haloBase.speed = 0.05
        haloBase.mainEmitter.birthRate = 6
        haloBase.mainEmitter.lifeSpan = 1.2
        haloBase.mainEmitter.size = 0.9
        haloBase.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.3
        haloBase.mainEmitter.opacityCurve = .quickFadeInOut
        haloBase.mainEmitter.blendMode = .additive
        haloBase.mainEmitter.isLightingEnabled = false

        core.components.set(coreBase)
        outer.components.set(outerBase)
        embers.components.set(embersBase)
        smoke.components.set(smokeBase)
        halo.components.set(haloBase)
    }

    // MARK: 팔레트

    func setTint(_ tint: FlameTint, animated: Bool = true) {
        guard tint != currentTint else { return }
        currentTint = tint
        fromPalette = palette
        toPalette = tint.palette
        if animated {
            blend = 0
            flash = 1
            spawnBurst(palette: toPalette)
        } else {
            blend = 1
            palette = toPalette
            applyPalette(palette)
        }
    }

    private func applyPalette(_ p: FlamePalette) {
        coreBase.mainEmitter.color = .evolving(start: .single(UIColor(p.core)), end: .single(UIColor(p.coreEnd.withAlpha(0.0))))
        outerBase.mainEmitter.color = .evolving(start: .single(UIColor(p.outer)), end: .single(UIColor(p.outerEnd.withAlpha(0.0))))
        embersBase.mainEmitter.color = .evolving(start: .single(UIColor(p.ember)), end: .single(UIColor(p.ember.withAlpha(0.0))))
        smokeBase.mainEmitter.color = .evolving(start: .single(UIColor(p.smoke.withAlpha(0.22))), end: .single(UIColor(p.smoke.withAlpha(0.0))))
        haloBase.mainEmitter.color = .evolving(start: .single(UIColor(p.glow.withAlpha(0.10))), end: .single(UIColor(p.glow.withAlpha(0.0))))
    }

    private func spawnBurst(palette p: FlamePalette) {
        let burst = Entity()
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.25, 0.25, 0.25]
        emitter.birthLocation = .volume
        emitter.birthDirection = .normal
        emitter.speed = 1.8
        emitter.speedVariation = 0.8
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 0.7
        emitter.mainEmitter.lifeSpanVariation = 0.2
        emitter.mainEmitter.size = 0.05
        emitter.mainEmitter.sizeVariation = 0.02
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.1
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.acceleration = [0, 1.2, 0]
        emitter.mainEmitter.dampingFactor = 1.5
        emitter.mainEmitter.color = .evolving(start: .single(UIColor(p.core)), end: .single(UIColor(p.glow.withAlpha(0))))
        emitter.mainEmitter.isLightingEnabled = false
        emitter.burstCount = 160
        emitter.burstCountVariation = 30
        burst.position = [0, 0.3, 0]
        burst.components.set(emitter)
        root.addChild(burst)
        emitter.burst()
        burst.components.set(emitter)
        burstEntities.append((burst, 1.5))
    }

    // MARK: 틱

    /// 30Hz 호출. 오디오 레벨 → 파티클/조명 파라미터.
    func update(deltaTime dt: Float, levels: AudioLevels, intensity: Float, reduceFlicker: Bool) {
        time += dt

        if blend < 1 {
            blend = min(1, blend + dt / blendDuration)
            let eased = blend * blend * (3 - 2 * blend)
            palette = .lerp(fromPalette, toPalette, eased)
            applyPalette(palette)
        }
        flash = max(0, flash - dt * 2.5)

        burstEntities = burstEntities.compactMap { entry in
            let remaining = entry.1 - dt
            if remaining <= 0 {
                entry.0.removeFromParent()
                return nil
            }
            return (entry.0, remaining)
        }

        let calm: Float = reduceFlicker ? 0.35 : 1.0
        let idle = 0.5 + 0.5 * sin(time * 1.7) * sin(time * 0.61 + 1.3)
        let bass = levels.isActive ? levels.bass : 0.18 * idle
        let mid = levels.isActive ? levels.mid : 0.15 * idle
        let treble = levels.isActive ? levels.treble : 0.1 * idle
        let rms = levels.isActive ? levels.rms : 0.15 * idle
        let beat = levels.beat * calm

        var coreEmitter = coreBase
        coreEmitter.speed = (0.8 + 0.7 * bass + 0.5 * beat) * intensity
        coreEmitter.mainEmitter.birthRate = (220 + 260 * bass + 120 * beat) * intensity
        coreEmitter.mainEmitter.size = 0.085 * (1 + 0.35 * rms) * intensity
        core.components.set(coreEmitter)

        var outerEmitter = outerBase
        outerEmitter.speed = (0.5 + 0.5 * mid) * intensity
        outerEmitter.mainEmitter.birthRate = (70 + 120 * mid) * intensity
        outerEmitter.mainEmitter.size = 0.15 * (1 + 0.25 * bass) * intensity
        outer.components.set(outerEmitter)

        var emberEmitter = embersBase
        emberEmitter.mainEmitter.birthRate = (25 + 90 * treble + 60 * beat) * intensity
        emberEmitter.speed = 0.6 + 0.4 * treble
        embers.components.set(emberEmitter)

        var smokeEmitter = smokeBase
        smokeEmitter.mainEmitter.birthRate = 12 + 6 * (1 - rms)
        smoke.components.set(smokeEmitter)

        var haloEmitter = haloBase
        haloEmitter.mainEmitter.size = 0.9 * (1 + 0.3 * rms) * intensity
        halo.components.set(haloEmitter)

        // 조명 플리커
        let noise = 0.5 + 0.5 * sin(time * 9.1) * sin(time * 13.7 + 0.4) * sin(time * 3.3)
        let flicker = 0.78 + 0.22 * noise * calm
        let lightIntensity = 900 * flicker * (1 + 0.6 * bass + 0.4 * beat) * intensity * (1 + 1.5 * flash)
        var lightColor = palette.glow
        if flash > 0 {
            lightColor = .lerp(lightColor, palette.core, flash * 0.6)
        }
        light.components.set(PointLightComponent(color: UIColor(lightColor), intensity: lightIntensity, attenuationRadius: 8))
    }
}
