# 불멍 라디오 (Bonfire Radio) — 테크 PRD

- 문서 버전: v1.0 (2026-09-29)
- 타깃: visionOS 27.0+, Xcode 27, Swift 5 언어 모드 + Approachable Concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- 타깃 이름: `MyApp` (제품 표시명 "불멍 라디오", 번들 ID `com.coulson.BonfireRadio`)
- 플랫폼 제한: `SUPPORTED_PLATFORMS = xros xrsimulator`, `TARGETED_DEVICE_FAMILY = 7`

---

## 1. 아키텍처 개요

```
┌──────────────── SwiftUI Scenes ────────────────┐
│ WindowGroup("lobby")  LobbyView / RoomControlView│
│ ImmersiveSpace("campfire") CampfireImmersiveView │
└───────────────┬────────────────────────────────┘
                │ @Environment(AppModel)
┌───────────────▼────────────────────────────────┐
│ AppModel (@Observable, MainActor)               │
│  - roomState: RoomState (fire tint, nowPlaying, hostID, seq)
│  - sessionController: SessionController?        │
│  - audio: BroadcastAudioEngine, analyzer levels │
│  - immersive state / mode(solo|shared)          │
└───────┬───────────────────┬────────────────────┘
        │                   │
┌───────▼─────────┐  ┌──────▼──────────────────────┐
│ SharePlay Layer │  │ Audio Layer                  │
│ RadioActivity   │  │ BroadcastAudioEngine         │
│ CampfireTemplate│  │  ├ DemoTrackSynth (SourceNode)│
│ SessionController│ │  ├ FilePlayer (PlayerNode)   │
│ RoomMessages    │  │  └ analysis tap → AudioAnalyzer│
└───────┬─────────┘  │ StreamPlayer (AVPlayer +     │
        │            │   PlaybackCoordinator + MTAudioProcessingTap)
        │            │ MicMonitor (solo/host)       │
        │            └──────┬──────────────────────┘
        │                   │ AudioLevels (bass/mid/treble/rms/beat)
┌───────▼───────────────────▼────────────────────┐
│ Immersive Layer (RealityKit)                    │
│ SkyDomeBuilder · CampfireBuilder · FireVisualizer│
│ ThrowableSpawner · FireReactorSystem(SceneEvents)│
└─────────────────────────────────────────────────┘
```

원칙
- **호스트 권위(host-authoritative)**: 방 상태의 진실은 방장 기기. 참가자는 이벤트를 제안(던지기)하고 방장이 확정 스냅샷을 브로드캐스트. 단, 지연 체감을 줄이기 위해 던지기 색 변화는 **낙관적 로컬 적용** 후 스냅샷으로 정합성 맞춤.
- **결정론적 입력**: 시각 효과는 모든 기기에서 동일 파라미터(팔레트, 강도)만 공유하고 파티클 난수는 로컬. "같은 색, 같은 리듬"이면 충분.
- **Combine 미사용**: async/await + `Observations` / `for await` 시퀀스로 관찰.

## 2. 모듈 상세

### 2.1 Scenes / App
- `BonfireRadioApp` (`MyApp.swift`): `WindowGroup(id: "lobby")` + `ImmersiveSpace(id: "campfire")`.
- `.immersionStyle(selection: $style, in: .progressive, .full)`, 기본 `.full`.
- 이머시브 오픈은 **SharePlay 세션 join 이후**에 수행(공유 좌표계 확립 후 열어야 위치 점프 방지).

### 2.2 AppModel
```swift
@Observable final class AppModel {
  enum Mode { case idle, solo, shared }
  var mode: Mode
  var roomState: RoomState          // 동기화 대상
  var isHost: Bool                  // 로컬 판단 + hostParticipantID 비교
  var localParticipantID: UUID?
  var audioLevels: AudioLevels      // 30Hz 갱신, 시각 레이어가 읽음
  var immersiveOpen: Bool
  var sessionController: SessionController?
  let audioEngine: BroadcastAudioEngine
}
```

### 2.3 RoomState & 메시지 (`RoomMessages.swift`)
```swift
nonisolated struct RoomState: Codable, Sendable, Equatable {
  var seq: UInt64                       // 단조 증가, 큰 값이 우선
  var hostParticipantID: UUID?
  var hostDisplayName: String
  var tint: FlameTint                   // 현재 불 색
  var tintChangedAt: TimeInterval       // 자동 복귀 타이머 기준(호스트 시계)
  var intensity: Float                  // 0.5~1.5
  var nowPlaying: NowPlaying?           // source, title, isPlaying, startedAt(host Date), positionAtStart
  var reduceFlicker: Bool
}
enum RoomMessage: Codable, Sendable {   // GroupSessionMessenger 페이로드
  case snapshot(RoomState)              // reliable, 호스트 → 전원(참가 시 캐치업 포함)
  case throwItem(ThrowEvent)            // unreliable → 시각 이펙트용(다른 기기에 아이템 궤적 재현)
  case requestTint(FlameTint, UInt64)   // 참가자 → 호스트(reliable). 호스트가 승인 후 snapshot
  case hostAnnounce(UUID, String)       // 호스트 선언
}
```
- 두 개의 `GroupSessionMessenger`: reliable(snapshot/request/announce), unreliable(throwItem).
- 새 참가자 감지(`session.$activeParticipants`) 시 호스트가 `snapshot`을 `.only(newcomers)`로 전송.
- 호스트 결정: `activate()`를 호출한 로컬이 `isHost = true`로 시작하고 `hostAnnounce` 송신. 이미 호스트 선언이 있으면 후발 선언은 무시(먼저 온 것 우선). 호스트 이탈 시 `activeParticipants` 중 가장 작은 UUID가 승계(v1 단순 규칙).

### 2.4 SharePlay 레이어
- `RadioActivity: GroupActivity` — `metadata.type = .listenTogether`, title "불멍 라디오", `sceneAssociationBehavior = .default`.
- `CampfireSpatialTemplate: SpatialTemplate` — 반경 2.4m 원형 8석. `Role.host` 좌석 1개(+z 정면) + 무역할 좌석 7개. 방향은 `.lookingAt(.app)`(기본). `SpatialTemplatePreference.custom(CampfireSpatialTemplate())`.
- `SystemCoordinator.configuration.supportsGroupImmersiveSpace = true`.
- 호스트는 `systemCoordinator.assignRole(CampfireSpatialTemplate.Role.host)` 요청(API 존재 여부는 컴파일 시 확인, 없으면 `SpatialTemplateConfiguration.defaultInitiatorRole` 사용).
- `groupImmersionStyle` 관찰 → 다른 참가자가 이머시브를 열면 "함께 들어가기" 제안(자동 강제 X).
- SharePlay 시뮬레이터 미지원 → 시뮬레이터/단일 기기 검증은 **솔로 모드**로 수행.

### 2.5 오디오 레이어
| 컴포넌트 | 기술 | 비고 |
|---|---|---|
| `BroadcastAudioEngine` | `AVAudioEngine`, `mainMixerNode`에 tap 설치(1024 프레임) | 데모 신스 / 로컬 파일(`AVAudioPlayerNode`) 재생, 볼륨 |
| `DemoTrackSynth` | `AVAudioSourceNode` 절차적 로파이 비트(킥·베이스·패드) | 저작권 없는 테스트 음원. 시작 시각 공유로 참가자 간 동기 재생(각 기기가 동일 시퀀스를 로컬 합성) |
| `StreamPlayer` | `AVPlayer` + `AVPlayerPlaybackCoordinator.coordinateWithSession` | 인터넷 라디오/HLS URL. 분석용 `MTAudioProcessingTap`(v1.1) |
| `MicMonitor` | `AVAudioEngine.inputNode` tap → RMS/밴드 | 솔로 모드·호스트 전용. FaceTime 통화 중에는 세션 인터럽션으로 비활성 처리 |
| `AudioAnalyzer` | Accelerate `vDSP` FFT 1024, Hann 창 | 밴드 에너지, RMS, 비트(플럭스 임계), 어택/릴리즈 스무딩 |
| 오디오 세션 | `.playback`(청취자) / `.playAndRecord`(솔로·마이크) `mode: .default`, `.mixWithOthers` 미사용 | 인터럽션·경로 변경 알림 처리 |

동기화 규칙
- 데모 트랙: `NowPlaying.startedAt`(호스트 `Date`) 기준으로 각 기기가 `Date.now - startedAt`만큼 진행한 위치에서 합성 시작. 시계 오차(수백 ms)는 비트 정합에 큰 문제 없음.
- 스트림 URL: 코디네이터가 rate/time을 맞춘다. UI 컨트롤은 호스트만 노출.
- 로컬 파일: v1은 호스트 기기에서만 재생(청취자에겐 "호스트 전용 음원" 표시). v2에서 청크 전송.

### 2.6 이머시브 레이어
- `SkyDomeBuilder`: `MeshResource.generateSphere(radius: 60)` + `UnlitMaterial(texture:)`, 텍스처는 CoreGraphics로 2048×1024 그라데이션+별(랜덤 시드 고정) 생성 → `TextureResource(image:options:)`. 안쪽이 보이도록 스케일 x = -1 반전.
- `CampfireBuilder`: 지면 디스크(`generateCylinder` 얇게), 돌 12개(`generateSphere` 비균일 스케일, PBR 회색 roughness 1), 장작 5개(`generateCylinder`, 갈색 PBR + 안쪽 에미시브 숯 실린더), 트리거 볼륨(구, 반경 0.45m, `CollisionComponent(mode: .trigger)`).
- `FireVisualizer`: 5개 자식 엔티티에 `ParticleEmitterComponent` 구성(설계 표 참조). `applyTint(_:)`는 `mainEmitter.color = .evolving(start:end:)`로 교체하고 라이트 색을 갱신. 크로스페이드는 `Entity.animate`가 아닌 30Hz 보간(HSB 보간)으로 수행.
- `FireReactorSystem`: `SceneEvents.Update` 구독(또는 `System`)에서 `audioLevels`를 읽어 `birthRate/speed/size/light.intensity`를 갱신하고 컴포넌트를 재설정. 갱신 빈도 30Hz로 제한(컴포넌트 재설정 비용 절감).
- `ThrowableSpawner`: 아이템 = `ModelEntity`(구/육면체/캡슐 조합) + `ManipulationComponent.configureEntity(...)`, `releaseBehavior = .stay`, `PhysicsBodyComponent(mode: .dynamic, mass 0.2)`, `CollisionComponent`. 릴리즈 시 관성 유지가 안 되는 환경을 위해 `ManipulationEvents.DidUpdateTransform`으로 최근 60ms 속도를 추정하여 `WillRelease`에서 `PhysicsMotionComponent.linearVelocity`를 주입(폴백). 불 트리거 `CollisionEvents.Began` → `AppModel.throwLanded(kind:)` → 낙관적 tint 적용 + `requestTint` 송신(호스트면 즉시 snapshot).
- 바구니 위치: 솔로 모드는 디바이스 앵커 없이 (0, 0.75, +1.9) 고정; SharePlay는 `systemCoordinator.localParticipantState.pose` 기준 앞 0.6m.

## 3. 상태 동기화 & 충돌 해소
- `seq`는 호스트만 증가. 참가자는 `requestTint(tint, localNonce)` 전송, 낙관적 적용은 `pendingTint`로 표시하고 다음 snapshot으로 확정/롤백.
- 스냅샷 수신 규칙: `incoming.seq > local.seq`일 때만 적용.
- 자동 복귀(90초): 호스트 타이머가 `tint = .default` snapshot 송신.

## 4. 권한/역할 모델
| 기능 | 방장 | 청취자 |
|---|---|---|
| 음원 선택/재생/정지 | ✅ | ❌ (UI 미노출, 메시지 무시) |
| 불 색 초기화, 강도 | ✅ | ❌ |
| 아이템 던지기 | ✅ | ✅ |
| 이머시브 열기 | ✅(그룹 스타일 제안) | ✅(개인 선택) |
| 마이크(FaceTime 음성) | 시스템 제어 | 시스템 제어(앱은 안내만) |

## 5. 빌드 설정 / 권한
- Entitlement: `com.apple.developer.group-session = true` — **주의(2026-09-29 확인)**: 현재 서명 팀(개인/무료 팀 `5Z8G42AVKD`)은 Group Activities 권한을 지원하지 않아 프로비저닝이 실패한다. 그래서 기본 `MyApp.entitlements`는 비워 두고, 키는 `MyApp.SharePlay.entitlements`에 보관했다. Apple Developer Program(유료) 팀으로 전환한 뒤 타깃의 `CODE_SIGN_ENTITLEMENTS`를 `MyApp/MyApp.SharePlay.entitlements`로 바꾸면 SharePlay가 활성화된다. 그 전까지 디바이스에서는 솔로 모드만 동작하며, SharePlay API 호출 시 런타임 이슈 로그("Using SharePlay requires… Group Activities capability")가 남는다.
- Info.plist: `NSMicrophoneUsageDescription`, `UIApplicationSceneManifest`(생성), `UIApplicationPreferredDefaultSceneSessionRole`, `UIBackgroundModes = [audio]`
- 프레임워크: SwiftUI, RealityKit, GroupActivities, AVFoundation/AVFAudio, Accelerate, CoreGraphics, Spatial

## 6. 성능 예산 (90Hz 유지)
- 파티클 총 출생률 ≤ 1,200/s, 살아있는 파티클 ≤ 3,000.
- 컴포넌트 재설정 30Hz, 스카이돔 텍스처 2048×1024 1장, 동적 라이트 1개.
- 던질 아이템 동시 활성 ≤ 24개(8명 × 3), 물리 dynamic 바디는 던져진 것만.

## 7. 테스트 전략
- 단위 테스트(Swift Testing, v1.1 테스트 타깃 추가): `FlameTint` 보간, `RoomState` seq 병합 규칙, `CampfireSpatialTemplate` 8석/역할 검증, `AudioAnalyzer` 밴드 계산(합성 사인파).
- 시뮬레이터: 솔로 모드 자동 진입 런치 인자 `autosolo`(DEBUG). 스크린샷으로 스카이돔·불꽃 확인.
- 디바이스: 손 던지기, 마이크 반응, SharePlay는 2대 이상 필요(단일 기기 계정은 메시지 경로 로그로 검증).

## 8. 리스크 & 대응
| 리스크 | 영향 | 대응 |
|---|---|---|
| FaceTime 중 마이크 접근 불가 | 목소리 반응 상실 | 음악 반응 중심 + 솔로 모드 목소리 반응 |
| 공간 페르소나 표시 상한 | 8명 동시 배치 불가 가능 | 좌석 8 정의, 초과 인원 FaceTime 창 안내 |
| ManipulationComponent 릴리즈 관성 미적용 | 던지기 실패 | 속도 추정 폴백 + 패널 "던지기" 버튼 |
| GroupSessionMessenger 지연/손실 | 색 불일치 | seq 스냅샷, 90초 자동 복귀 |
| 스트림 분석 탭 복잡도 | 비주얼 무반응 | v1: 데모 트랙 분석 확정, 스트림은 idle+볼륨 폴백 |

## 9. 로드맵
- v1 (이번): 위 전체 MVP.
- v1.1: 스트림 `MTAudioProcessingTap`, 단위 테스트 타깃, 오너먼트 Now Playing.
- v2: 자체 오디오 서버(WebRTC SFU, 예: LiveKit)로 **서버 강제 방장 마이크/음악 송출 권한**, 호스트 파일 실시간 스트리밍, MusicKit 카탈로그, 공개 방 목록.
