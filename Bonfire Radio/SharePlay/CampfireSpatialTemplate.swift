import Foundation
import GroupActivities

/// 모닥불(원점)을 중심으로 반경 2.4m 원형 8석. 방 생성자는 정면(+z) 방장 좌석에 앉는다.
nonisolated struct CampfireSpatialTemplate: SpatialTemplate {
    nonisolated enum Role: String, SpatialTemplateRole {
        case host
    }

    static let seatCount = 8
    static let radius: Double = 2.4

    let configuration = SpatialTemplateConfiguration(defaultInitiatorRole: Role.host)

    var elements: [any SpatialTemplateElement] {
        (0..<Self.seatCount).map { index in
            let angle = Double(index) / Double(Self.seatCount) * 2 * Double.pi
            let x = Self.radius * sin(angle)
            let z = Self.radius * cos(angle)
            // 시스템은 배열 순서대로 좌석을 채운다. 방장 좌석(역할 필요)을 먼저 두고 나머지는 자유석.
            return SpatialTemplateSeatElement(
                position: .app.offsetBy(x: x, z: z),
                direction: .lookingAt(.app),
                role: index == 0 ? Role.host : nil
            )
        }
    }

    /// 좌석 인덱스의 위치(이머시브 씬 좌표계와 동일: 원점 = 모닥불).
    static func seatPosition(index: Int) -> SIMD3<Float> {
        let angle = Float(index) / Float(seatCount) * 2 * Float.pi
        return SIMD3<Float>(Float(radius) * sin(angle), 0, Float(radius) * cos(angle))
    }
}
