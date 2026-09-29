import Foundation

/// RGBA 색상(0...1). 메시지·오디오 스레드에서도 쓰이므로 nonisolated 값 타입.
nonisolated struct FlameColor: Codable, Sendable, Equatable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    func withAlpha(_ alpha: Float) -> FlameColor {
        FlameColor(r, g, b, alpha)
    }

    static func lerp(_ x: FlameColor, _ y: FlameColor, _ t: Float) -> FlameColor {
        let k = max(0, min(1, t))
        return FlameColor(x.r + (y.r - x.r) * k,
                          x.g + (y.g - x.g) * k,
                          x.b + (y.b - x.b) * k,
                          x.a + (y.a - x.a) * k)
    }
}

/// 모닥불 한 벌의 색 구성.
nonisolated struct FlamePalette: Codable, Sendable, Equatable {
    /// 코어 불꽃 시작(가장 뜨거운 중심) → 끝
    var core: FlameColor
    var coreEnd: FlameColor
    /// 외곽 불꽃 혀 시작 → 끝
    var outer: FlameColor
    var outerEnd: FlameColor
    /// 위로 떠오르는 불씨
    var ember: FlameColor
    /// 광륜과 동적 조명
    var glow: FlameColor
    /// 연기
    var smoke: FlameColor

    static func lerp(_ x: FlamePalette, _ y: FlamePalette, _ t: Float) -> FlamePalette {
        FlamePalette(core: .lerp(x.core, y.core, t),
                     coreEnd: .lerp(x.coreEnd, y.coreEnd, t),
                     outer: .lerp(x.outer, y.outer, t),
                     outerEnd: .lerp(x.outerEnd, y.outerEnd, t),
                     ember: .lerp(x.ember, y.ember, t),
                     glow: .lerp(x.glow, y.glow, t),
                     smoke: .lerp(x.smoke, y.smoke, t))
    }
}

/// 불 색 프리셋. 불꽃 반응(화학) 모티프.
nonisolated enum FlameTint: String, Codable, CaseIterable, Sendable {
    case wood
    case sodium
    case copper
    case lithium
    case potassium
    case boron
    case strontium
    case magnesium
    case stardust

    /// 90초 후 자동으로 돌아가는 기본 불.
    static let `default`: FlameTint = .wood

    var displayName: String {
        switch self {
        case .wood: "장작불"
        case .sodium: "노란 불꽃"
        case .copper: "청록 불꽃"
        case .lithium: "진홍 불꽃"
        case .potassium: "연보라 불꽃"
        case .boron: "연두 불꽃"
        case .strontium: "선홍 불꽃"
        case .magnesium: "백색 불꽃"
        case .stardust: "별빛 불꽃"
        }
    }

    var palette: FlamePalette {
        switch self {
        case .wood:
            FlamePalette(core: FlameColor(1.00, 0.95, 0.60), coreEnd: FlameColor(1.00, 0.45, 0.05),
                         outer: FlameColor(1.00, 0.55, 0.10), outerEnd: FlameColor(0.80, 0.15, 0.00),
                         ember: FlameColor(1.00, 0.60, 0.20), glow: FlameColor(1.00, 0.55, 0.20),
                         smoke: FlameColor(0.35, 0.33, 0.30))
        case .sodium:
            FlamePalette(core: FlameColor(1.00, 1.00, 0.75), coreEnd: FlameColor(1.00, 0.85, 0.20),
                         outer: FlameColor(1.00, 0.80, 0.20), outerEnd: FlameColor(0.90, 0.50, 0.05),
                         ember: FlameColor(1.00, 0.85, 0.30), glow: FlameColor(1.00, 0.80, 0.30),
                         smoke: FlameColor(0.36, 0.34, 0.28))
        case .copper:
            FlamePalette(core: FlameColor(0.80, 1.00, 0.90), coreEnd: FlameColor(0.20, 0.95, 0.60),
                         outer: FlameColor(0.30, 0.90, 0.50), outerEnd: FlameColor(0.05, 0.50, 0.30),
                         ember: FlameColor(0.50, 1.00, 0.60), glow: FlameColor(0.30, 0.90, 0.60),
                         smoke: FlameColor(0.28, 0.34, 0.32))
        case .lithium:
            FlamePalette(core: FlameColor(1.00, 0.80, 0.80), coreEnd: FlameColor(1.00, 0.20, 0.30),
                         outer: FlameColor(0.95, 0.15, 0.30), outerEnd: FlameColor(0.50, 0.02, 0.10),
                         ember: FlameColor(1.00, 0.40, 0.50), glow: FlameColor(1.00, 0.25, 0.35),
                         smoke: FlameColor(0.36, 0.30, 0.31))
        case .potassium:
            FlamePalette(core: FlameColor(0.95, 0.90, 1.00), coreEnd: FlameColor(0.75, 0.55, 1.00),
                         outer: FlameColor(0.70, 0.50, 0.95), outerEnd: FlameColor(0.35, 0.20, 0.60),
                         ember: FlameColor(0.85, 0.70, 1.00), glow: FlameColor(0.70, 0.55, 1.00),
                         smoke: FlameColor(0.32, 0.30, 0.36))
        case .boron:
            FlamePalette(core: FlameColor(0.90, 1.00, 0.80), coreEnd: FlameColor(0.55, 1.00, 0.30),
                         outer: FlameColor(0.40, 0.95, 0.30), outerEnd: FlameColor(0.10, 0.50, 0.15),
                         ember: FlameColor(0.70, 1.00, 0.50), glow: FlameColor(0.50, 1.00, 0.35),
                         smoke: FlameColor(0.30, 0.34, 0.29))
        case .strontium:
            FlamePalette(core: FlameColor(1.00, 0.85, 0.70), coreEnd: FlameColor(1.00, 0.35, 0.10),
                         outer: FlameColor(1.00, 0.25, 0.05), outerEnd: FlameColor(0.60, 0.05, 0.02),
                         ember: FlameColor(1.00, 0.45, 0.15), glow: FlameColor(1.00, 0.30, 0.10),
                         smoke: FlameColor(0.36, 0.31, 0.29))
        case .magnesium:
            FlamePalette(core: FlameColor(1.00, 1.00, 1.00), coreEnd: FlameColor(0.85, 0.90, 1.00),
                         outer: FlameColor(0.90, 0.95, 1.00), outerEnd: FlameColor(0.50, 0.60, 0.80),
                         ember: FlameColor(1.00, 1.00, 1.00), glow: FlameColor(0.90, 0.95, 1.00),
                         smoke: FlameColor(0.40, 0.40, 0.42))
        case .stardust:
            FlamePalette(core: FlameColor(0.80, 1.00, 1.00), coreEnd: FlameColor(0.20, 0.80, 1.00),
                         outer: FlameColor(0.30, 0.60, 1.00), outerEnd: FlameColor(0.25, 0.10, 0.60),
                         ember: FlameColor(0.60, 0.95, 1.00), glow: FlameColor(0.35, 0.70, 1.00),
                         smoke: FlameColor(0.28, 0.30, 0.38))
        }
    }
}
