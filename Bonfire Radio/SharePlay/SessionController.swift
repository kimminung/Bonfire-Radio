import Foundation
import SwiftUI
import Combine // GroupSession의 @Published 속성을 `.values`로 관찰하기 위한 최소 사용
import GroupActivities
import Spatial
import OSLog

private let logger = Logger(subsystem: "com.coulson.BonfireRadio", category: "session")

/// GroupSession 수명주기, 메시지 송수신, 공간 상태를 관리한다.
@Observable
final class SessionController {
    let session: GroupSession<RadioActivity>
    let coordinator: SystemCoordinator
    private let reliable: GroupSessionMessenger
    private let unreliable: GroupSessionMessenger
    private weak var appModel: AppModel?
    private var tasks: [Task<Void, Never>] = []

    private(set) var participantCount = 1
    private(set) var isSpatial = false
    /// 좌석 배정 시점의 로컬 참가자 위치(공유 좌표, 원점 = 모닥불).
    private(set) var localSeatPosition: SIMD3<Float>?
    /// 그룹의 최근 몰입 상태. nil = 아직 없음, true = 누군가 이머시브를 열었음, false = 닫음.
    private(set) var groupImmersionOpen: Bool?

    var localParticipantID: UUID { session.localParticipant.id }

    init?(session: GroupSession<RadioActivity>, appModel: AppModel) async {
        guard let coordinator = await session.systemCoordinator else {
            logger.error("SystemCoordinator 없음")
            return nil
        }
        self.session = session
        self.coordinator = coordinator
        self.appModel = appModel
        self.reliable = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        self.unreliable = GroupSessionMessenger(session: session, deliveryMode: .unreliable)

        var config = coordinator.configuration
        config.supportsGroupImmersiveSpace = true
        config.spatialTemplatePreference = .custom(CampfireSpatialTemplate())
        coordinator.configuration = config

        observeMessages()
        observeParticipants()
        observeSpatialState()
        observeGroupImmersion()

        session.join()
        logger.notice("세션 참가 요청: \(session.id)")
    }

    // MARK: 송신

    func send(_ message: RoomMessage, to participants: Participants = .all) {
        Task {
            do {
                try await reliable.send(message, to: participants)
            } catch {
                logger.error("메시지 송신 실패: \(error.localizedDescription)")
            }
        }
    }

    func sendUnreliable(_ message: RoomMessage) {
        Task {
            try? await unreliable.send(message, to: .all)
        }
    }

    // MARK: 종료

    func leave() {
        cancelTasks()
        session.leave()
    }

    func endForEveryone() {
        cancelTasks()
        session.end()
    }

    private func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: 관찰

    private func observeMessages() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (message, context) in reliable.messages(of: RoomMessage.self) {
                appModel?.handle(message: message, from: context.source.id)
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (message, context) in unreliable.messages(of: RoomMessage.self) {
                appModel?.handle(message: message, from: context.source.id)
            }
        })
    }

    private func observeParticipants() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            var previous = Set<Participant>()
            for await active in session.$activeParticipants.values {
                participantCount = active.count
                let localID = self.session.localParticipant.id
                let newcomers = active.subtracting(previous).filter { $0.id != localID }
                previous = active
                if !newcomers.isEmpty {
                    appModel?.participantsJoined(newcomers)
                }
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in session.$state.values {
                switch state {
                case .joined:
                    appModel?.sessionDidJoin()
                case .invalidated(let reason):
                    logger.notice("세션 무효화: \(reason.localizedDescription)")
                    appModel?.sessionDidInvalidate()
                    return
                default:
                    break
                }
            }
        })
    }

    private func observeSpatialState() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in coordinator.localParticipantStates {
                isSpatial = state.isSpatial
                if let pose = state.pose {
                    localSeatPosition = SIMD3<Float>(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
                }
            }
        })
    }

    private func observeGroupImmersion() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await style in coordinator.groupImmersionStyle {
                groupImmersionOpen = style != nil
                appModel?.groupImmersionChanged(isOpen: style != nil)
            }
        })
    }
}
