import Foundation
import CoreTransferable
import GroupActivities

/// "불멍 라디오" SharePlay 활동. Transferable 채택으로 ShareLink(시스템 공유 시트)에서 초대할 수 있다.
nonisolated struct RadioActivity: GroupActivity, Transferable, Sendable {
    static let activityIdentifier = "com.coulson.BonfireRadio.radio"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "불멍 라디오"
        metadata.subtitle = "모닥불에 둘러앉아 함께 듣기"
        metadata.type = .listenTogether
        metadata.supportsContinuationOnTV = false
        return metadata
    }
}
