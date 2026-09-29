# 불멍 라디오 — 태스크 문서

상태 표기: `[ ]` 대기 · `[~]` 진행 · `[x]` 완료 · `[!]` 블록/보류
갱신: 2026-09-29 21:00

## Phase 0 — 문서 & 프로젝트 설정
- [x] T-001 DesignPRD.md 작성
- [x] T-002 TechPRD.md 작성
- [x] T-003 Tasks.md 작성
- [x] T-004 타깃 visionOS 전용화(`SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY=7`), 번들 ID `com.coulson.BonfireRadio`, 표시명 "불멍 라디오"
- [x] T-005 Info.plist: 마이크 문구, 씬 매니페스트, 기본 씬 역할, 백그라운드 오디오
- [!] T-006 Entitlement `com.apple.developer.group-session` — 개인(무료) 팀은 Group Activities 미지원으로 프로비저닝 실패. 키를 `MyApp.SharePlay.entitlements`에 보관, 기본 엔타이틀먼트는 비움. **유료 팀 전환 후 `CODE_SIGN_ENTITLEMENTS` 교체 필요.**

## Phase 1 — 앱 골격
- [x] T-101 `BonfireRadioApp`: WindowGroup + ImmersiveSpace, immersionStyle(.progressive/.full)
- [x] T-102 `AppModel` (@Observable): 모드, RoomState, 세션 참조, 던지기 큐
- [x] T-103 `LobbyView`: 방 만들기(FaceTime 중) / 초대해서 방 만들기(ShareLink) / 혼자 불멍
- [x] T-104 `RoomControlView`: 방장 패널(ON AIR, 음원, 불 색 초기화, 강도, 깜빡임 줄이기), 청취자 패널(안내), 던지기 폴백 버튼, 공간 열기/닫기
- [x] T-105 DEBUG 런치 인자 `autosolo` / `autodemo` / `autothrow`
  - 검증: 시뮬레이터 실행 → 이머시브 열림 → 불꽃 표시 (스크린샷 확인 2026-09-29)

## Phase 2 — 이머시브 정적 요소
- [x] T-201 `SkyDomeBuilder`: 절차적 밤하늘(그라데이션+은하수+별 1800개) → 반경 60m 구, faceCulling .front
- [x] T-202 `CampfireBuilder`: 재 바닥, 돌 12개, 장작 5개 티피 + 가로 장작 2개, 숯 에미시브
- [x] T-203 모닥불 PointLight + 플리커(FireVisualizer 내)
- [x] T-204 불 트리거 볼륨(반경 0.5m, .trigger)

## Phase 3 — 모닥불 비주얼라이저
- [x] T-301 `FlameTint` 팔레트 9종 + 선형 보간
- [x] T-302 `FireVisualizer`: 코어/외곽/불씨/연기/광륜 5 이미터
- [x] T-303 `AudioAnalyzer`(vDSP FFT 1024, hop 256, 밴드·RMS·비트, 자동 게인, 어택/릴리즈)
- [x] T-304 30Hz 오디오→파라미터 매핑, 조명 플리커, 틴트 1.5초 크로스페이드 + 버스트
- [x] T-305 "깜빡임 줄이기" 옵션 반영
  - 검증: 데모 트랙 재생 중 스크린샷에서 불꽃 반응 확인. 비트 타이밍 정합은 디바이스에서 육안 확인 필요

## Phase 4 — 던지기 인터랙션
- [x] T-401 `ThrowableKind` 8종
- [x] T-402 `ThrowableSpawner`: 바구니 3슬롯, ManipulationComponent(.stay), 키네마틱→다이내믹 전환, 2초 리스폰
- [x] T-403 릴리즈 속도 추정(DidUpdateTransform 최근 90ms → WillRelease)
- [x] T-404 충돌 → 버스트 + 틴트 변경 (효과음은 미구현 → T-406)
- [x] T-405 패널 "던지기" 폴백(포물선 발사) — 시뮬레이터에서 구리 조각 → 청록 불꽃 전환 확인
- [ ] T-406 던지기/색 변화 효과음(에셋 또는 합성)
- [ ] T-407 실기기 손 던지기 감도 튜닝(속도 배율 1.15, 상한 8m/s)

## Phase 5 — SharePlay (코드 완료, 권한 문제로 디바이스 검증 보류)
- [x] T-501 `RadioActivity` (GroupActivity + Transferable, listenTogether)
- [x] T-502 `CampfireSpatialTemplate` 8석 원형(반경 2.4m), 방장 역할 = 방 생성자(defaultInitiatorRole)
- [x] T-503 `SessionController`: sessions() 관찰, join, coordinator 설정(supportsGroupImmersiveSpace, custom template), 메시지 송수신(reliable/unreliable)
- [x] T-504 `RoomMessage` + seq 병합 + 신규 참가자 캐치업 스냅샷
- [x] T-505 호스트 선언/동시 선언 타이브레이크(UUID 작은 쪽)
- [x] T-506 groupImmersionStyle → "함께 들어갈까요?" 알림
- [x] T-507 세션 무효화 시 정리
- [!] T-508 2대 디바이스 실검증 — Group Activities 권한(유료 팀) 필요
- [ ] T-509 호스트 이탈 시 승계 규칙 구현(현재 미구현)

## Phase 6 — 오디오
- [x] T-601 `BroadcastAudioEngine` (AVAudioEngine, 믹서 탭)
- [x] T-602 `DemoTrackSynth` 절차적 로파이 트랙(84 BPM, Am–F–C–G), 시작 시각 동기, 렌더 경로 분석
- [x] T-603 `StreamPlayer` (AVPlayer + PlaybackCoordinator)
- [x] T-604 마이크 모니터(솔로 모드 토글)
- [x] T-605 로컬 파일 가져오기(방장 기기만)
- [~] T-606 오디오 세션: 카테고리 설정은 백그라운드 스레드로 이동. 인터럽션/경로 변경 알림 처리 미구현
- [ ] T-607 (v1.1) 스트림 MTAudioProcessingTap 분석 (현재 스트림은 고정 은은한 반응)
- [ ] T-608 visionOS 27에서 deprecated된 `connect(_:to:format:)`/`installTap`/`play()` 대체 API로 교체
- [ ] T-609 이머시브 진입 시 SwiftUI 런타임 이슈 "Entity returned from EntityWrapper.makeEntity was already parented" 원인 조사(어태치먼트 제거·던진 아이템 컨테이너 분리 후에도 잔존, 표시/동작 영향 없음, 윈도우만 띄우면 미발생)

## Phase 7 — 검증 & 마무리
- [x] T-701 디바이스 빌드(Debug-xros) 통과 — 엔타이틀먼트 비운 뒤 성공
- [x] T-702 시뮬레이터 빌드·실행·스크린샷(autosolo autodemo autothrow)
- [ ] T-703 접근성 점검(VoiceOver 실기기, Dynamic Type 확대 레이아웃)
- [ ] T-704 (v1.1) Swift Testing 타깃: FlameTint 보간, RoomState 병합, 템플릿 좌석 수
- [x] T-705 메모리/문서 최신화

## 백로그 (v2)
- [ ] B-01 자체 오디오 서버(WebRTC SFU)로 서버 강제 마이크 권한 + 호스트 파일 실시간 스트리밍
- [ ] B-02 MusicKit 카탈로그 검색/재생
- [ ] B-03 공개 방 목록/딥링크
- [ ] B-04 모닥불 스킨(화로, 캠핑 랜턴)
- [ ] B-05 다른 참가자의 던지기 궤적 재현(현재 색 변화만 동기)
