import Foundation

/// 모닥불에 던질 수 있는 아이템. 각 아이템은 불 색 하나에 대응한다.
nonisolated enum ThrowableKind: String, Codable, CaseIterable, Sendable {
    case salt
    case copper
    case lithium
    case potassium
    case boron
    case strontium
    case magnesium
    case stardust

    nonisolated enum Shape: Sendable {
        case sphere
        case cube
        case cylinder
        case crystal
    }

    var name: String {
        switch self {
        case .salt: "소금 한 줌"
        case .copper: "구리 조각"
        case .lithium: "리튬 돌"
        case .potassium: "칼륨 가루"
        case .boron: "붕산 결정"
        case .strontium: "스트론튬 알"
        case .magnesium: "마그네슘 리본"
        case .stardust: "별가루"
        }
    }

    var tint: FlameTint {
        switch self {
        case .salt: .sodium
        case .copper: .copper
        case .lithium: .lithium
        case .potassium: .potassium
        case .boron: .boron
        case .strontium: .strontium
        case .magnesium: .magnesium
        case .stardust: .stardust
        }
    }

    var shape: Shape {
        switch self {
        case .salt: .cube
        case .copper: .cylinder
        case .lithium: .sphere
        case .potassium: .sphere
        case .boron: .crystal
        case .strontium: .sphere
        case .magnesium: .cylinder
        case .stardust: .crystal
        }
    }

    /// 아이템 본체 색(불 색과는 다르게 물체답게).
    var bodyColor: FlameColor {
        switch self {
        case .salt: FlameColor(0.95, 0.95, 0.92)
        case .copper: FlameColor(0.72, 0.45, 0.20)
        case .lithium: FlameColor(0.55, 0.55, 0.58)
        case .potassium: FlameColor(0.80, 0.78, 0.90)
        case .boron: FlameColor(0.75, 0.95, 0.80)
        case .strontium: FlameColor(0.85, 0.30, 0.25)
        case .magnesium: FlameColor(0.85, 0.87, 0.90)
        case .stardust: FlameColor(0.55, 0.85, 1.00)
        }
    }

    var isMetallic: Bool {
        switch self {
        case .copper, .magnesium, .lithium: true
        default: false
        }
    }

    var symbolName: String {
        switch self {
        case .salt: "cube.fill"
        case .copper: "cylinder.fill"
        case .lithium: "circle.fill"
        case .potassium: "circle.dotted"
        case .boron: "diamond.fill"
        case .strontium: "circle.fill"
        case .magnesium: "capsule.fill"
        case .stardust: "sparkles"
        }
    }
}
