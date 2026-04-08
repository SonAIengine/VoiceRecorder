# SonLife Agent System — Vision & Architecture (iOS Client 관점)

> Personal Life OS를 위한 멀티에이전트 시스템 설계 문서
> 작성: 2026-04-08 | 상태: Draft v1
>
> **이 문서는 `SonAIengine/sonlife` (백엔드) 레포의 동일 문서와 짝을 이룬다.**
> 백엔드 구현 상세는 [sonlife/docs/AGENT-SYSTEM-VISION.md](https://github.com/SonAIengine/sonlife/blob/main/docs/AGENT-SYSTEM-VISION.md) 참조.

---

## 1. Vision (한 줄)

> **나에 대한 모든 인풋을 하나로 모아서 전체 컨텍스트로 유지하고, 멀티에이전트가 내 일을 대신 수행한다.**
> — 메일 작성, 코드 작업, 일정 조정, 리서치, 관계 응대까지.

SonLife iOS 앱은 이 시스템의 **유일한 컨트롤 타워**다. 모든 에이전트 실행은 서버에서 일어나고, iOS는 **명령 발행 · 승인 · 모니터링**만 담당한다.

## 2. iOS 앱이 담당하는 역할

```
┌──────────────────────────────────────────────────────────┐
│  SonLife iOS App — Control Tower                         │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  1. Command Interface                           │     │
│  │     · 자연어 명령 입력 ("A교수한테 답장 써줘")    │     │
│  │     · 음성 명령 (STT → text)                     │     │
│  │     · 빠른 액션 (Siri Shortcuts)                 │     │
│  └─────────────────────────────────────────────────┘     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  2. HITL Approval UI                            │     │
│  │     · APNs 푸시 수신                             │     │
│  │     · 초안/변경사항 미리보기                      │     │
│  │     · 승인/거절/수정 후 재전송                    │     │
│  │     · Diff view (코드/텍스트)                    │     │
│  └─────────────────────────────────────────────────┘     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  3. Agent Dashboard                             │     │
│  │     · 오늘 실행 기록 (agent run timeline)        │     │
│  │     · 에이전트별 상태 (idle/running/pending)     │     │
│  │     · 오늘 비용 (토큰/USD)                        │     │
│  │     · 로그 뷰 (실패 원인 추적)                    │     │
│  └─────────────────────────────────────────────────┘     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  4. Lifelog Viewer (Phase 2)                    │     │
│  │     · Daily Note 타임라인                        │     │
│  │     · 소스별 필터                                │     │
│  │     · 검색                                       │     │
│  └─────────────────────────────────────────────────┘     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │  5. Voice Recording (현재 완료)                  │     │
│  │     · LifeLog 연속 녹음 (5분 청킹)               │     │
│  │     · 실시간 STT + 화자 분리                     │     │
│  │     · Live Activity / Dynamic Island             │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

**원칙**: iOS는 **절대로 LLM을 직접 호출하지 않는다**. 모든 에이전트 실행은 서버에서. iOS는 얇은 클라이언트.

## 3. Vision 전체 (백엔드 포함)

### 3.1 Why
1. **컨텍스트 단절 해결** — 에이전트가 내 lifelog를 알고 시작하면 매번 설명 불필요
2. **반복 작업 위임** — 메일, 코드, 일정, PR 초안, 리서치 자동화
3. **안전한 자율성** — HITL 게이트 + 권한 시스템
4. **단일 통제점** — iOS 앱이 유일한 컨트롤 타워

### 3.2 Core Principles
1. **Self-Context First** — 모든 에이전트는 "손성준은 누구이며 지금 무엇을 하고 있는가"를 주입받음
2. **HITL by Default** — 외부 부작용은 기본 승인 게이트
3. **Plan-then-Delegate** — Orchestrator 중앙 집중, specialist 끼리 직접 대화 금지
4. **Specialist > Generalist** — 도메인별 전용 에이전트
5. **Observable Everything** — 모든 실행은 기록, 재현 가능

### 3.3 Architecture 요약
```
iOS 앱
  ↕ (APNs + REST)
Orchestrator (Router + Planner)
  ↓
[CodingAgent (Claude Agent SDK)]
[EmailAgent (PydanticAI + HITL)]
[ResearchAgent]
[PlanningAgent]
[SocialAgent]
  ↕
[Self-Context Layer] [Permission Gate] [Session Store]
[Hook Registry]      [Memory]          [Budget Gate]
```

상세는 백엔드 레포 문서 참조. 여기서는 iOS 앱이 의존하는 API 계약에 집중.

## 4. iOS ↔ 서버 API 계약

### 4.1 기존 (완료)
| 엔드포인트 | 용도 |
|---|---|
| `POST /api/transcribe` | 음성 → STT |
| `POST /api/session/complete` | 세션 완료 → 요약 |
| `POST /api/devices/register` | APNs 디바이스 등록 |
| `POST /api/feedback` | H3-A 피드백 |
| `GET /api/lifelog/entries` | Daily Note 조회 |

### 4.2 신규 필요 (Phase A)

#### `POST /api/command` — 에이전트 명령 발행
```json
// Request
{
  "input": "장하렴한테 어제 회의 내용 정리해서 보내줘",
  "input_type": "text",      // "text" | "voice"
  "source": "ios_app",
  "urgency": "normal"        // "low" | "normal" | "high"
}
// Response (즉시)
{
  "command_id": "cmd_abc123",
  "status": "accepted",
  "estimated_seconds": 30,
  "plan_preview": {          // 실행 전 plan 미리보기
    "goal": "장하렴에게 회의록 메일 발송",
    "steps": [
      {"agent": "research", "task": "장하렴과 어제 회의 lifelog 조회"},
      {"agent": "email",    "task": "회의록 메일 초안 작성"},
      {"agent": "email",    "task": "발송 (승인 필요)"}
    ]
  }
}
```

#### `GET /api/commands/{command_id}` — 명령 상태 조회
```json
{
  "command_id": "cmd_abc123",
  "status": "pending_hitl",  // "accepted" | "running" | "pending_hitl" | "completed" | "failed"
  "current_step": 3,
  "pending_token": "tok_xyz",  // HITL 대기 중이면
  "result": null
}
```

#### `POST /api/approval/{token}` — 승인/거절
```json
// Request
{
  "decision": "approve",      // "approve" | "reject" | "modify"
  "modified_args": {          // modify 시 변경된 인자
    "body": "수정된 메일 본문..."
  },
  "reason": null              // reject 시 이유
}
// Response
{
  "status": "resumed",
  "execution_status": "running"
}
```

#### `GET /api/sessions` — 에이전트 실행 기록 (대시보드)
```json
{
  "sessions": [
    {
      "id": "sess_001",
      "agent_name": "email",
      "triggered_by": "ios_command",
      "status": "completed",
      "started_at": "2026-04-08T10:30:00+09:00",
      "ended_at": "2026-04-08T10:30:47+09:00",
      "cost_usd": 0.012,
      "tokens": {"input": 2341, "output": 512},
      "summary": "장하렴에게 회의록 메일 발송 완료"
    }
  ],
  "total_cost_today": 0.34,
  "budget_remaining_today": 4.66
}
```

#### `GET /api/sessions/{id}` — 세션 상세 (디버깅용)
```json
{
  "id": "sess_001",
  "self_context": "...",      // 주입된 컨텍스트 전문
  "plan": {...},
  "tool_calls": [...],
  "messages": [...],
  "usage": {...},
  "error": null
}
```

### 4.3 APNs Payload

#### 승인 요청
```json
{
  "aps": {
    "alert": {
      "title": "장하렴 메일 발송 승인",
      "body": "회의록 초안이 준비되었습니다"
    },
    "category": "APPROVAL_REQUEST",
    "mutable-content": 1
  },
  "type": "approval_request",
  "token": "tok_xyz",
  "preview": {
    "agent": "email",
    "action": "send_email",
    "summary": "장하렴에게 '어제 회의록' 메일 발송"
  }
}
```

iOS 앱은 `token`을 받아서 서버에 `GET /api/commands/{command_id}` 또는 별도 엔드포인트로 full context를 불러와 승인 화면을 구성.

#### 실행 완료 알림
```json
{
  "aps": {
    "alert": {
      "title": "작업 완료",
      "body": "장하렴에게 메일 발송 완료"
    }
  },
  "type": "command_completed",
  "command_id": "cmd_abc123"
}
```

## 5. iOS 구현 로드맵

### Phase A — Control Tower v1 (백엔드 Phase A와 동시)
**목표**: 텍스트 명령 → 서버 전송 → HITL 승인 → 결과 확인 전 경로

**iOS 작업**:
1. **CommandInputView**
   - 자연어 입력 TextField + 전송 버튼
   - `POST /api/command` 호출
   - Plan preview 표시 (실행 전 확인)
   
2. **ApprovalView** (H3-A 피드백 UI 패턴 재사용)
   - APNs `type=approval_request` 수신 핸들러
   - 초안 미리보기 (메일이면 To/Subject/Body)
   - 수정 가능 (modify 액션)
   - 승인/거절/수정 → `POST /api/approval/{token}`
   
3. **AgentDashboardView**
   - `GET /api/sessions` 조회
   - 오늘 실행 기록 리스트
   - 에이전트별 상태 표시
   - 비용 표시
   
4. **UNUserNotificationCenter 확장**
   - `APPROVAL_REQUEST` 카테고리 등록
   - 알림 액션 (Quick Approve / Quick Reject)
   - `mutable-content` 활용한 rich preview
   
5. **APIClient 확장**
   - `CommandAPI` 모델 (Codable)
   - `SessionsAPI` 모델
   - `ApprovalAPI` 모델

### Phase B — Code Agent 통합
- `ApprovalView`에 **코드 diff 뷰어** 추가
- git push 승인 화면 (파일별 변경사항 + 테스트 결과)
- PR 링크 열기

### Phase C — Voice Command
- 명령 입력을 음성으로 (기존 STT 재사용)
- "Hey Siri, SonLife에게 XXX 시켜줘"

### Phase D — Dashboard 고도화
- 에이전트별 성능 그래프
- 비용 추이
- 실패 로그 상세 뷰

### Phase E — Proactive Suggestions
- 에이전트가 "이거 자동화할까요?" 제안 수신
- 사용자가 자율 실행 opt-in

## 6. iOS 설계 원칙

### 6.1 얇은 클라이언트
- **LLM 직접 호출 금지** — 모든 LLM은 서버
- **비즈니스 로직 최소화** — UI + 상태 표시에 집중
- **서버가 진실의 근원** — 상태는 서버에서 fetch, 캐시는 오프라인 대응용만

### 6.2 Rich HITL UX
사용자가 자주 보게 될 화면은 승인 화면이다. 공들여야 함:
- 컨텍스트 충분 제공 ("왜 이 메일을 보내려고 하는가")
- 수정 가능 (초안을 편집)
- 빠른 승인 패스 (Face ID 1회 터치)
- 거절 시 학습 피드백 ("왜 거절했는지" → synaptic-memory 강화)

### 6.3 Offline 내성
- APNs는 iOS 오프라인에서도 나중에 전달됨
- 승인 수신 → 서버 응답 실패 시 재시도 큐
- 대시보드는 마지막 성공 fetch 캐시 표시

### 6.4 Design System 일관성
- H3-A FeedbackView 패턴 (Accept/Decline) 재사용
- SF Symbols 기본
- Dark mode 지원

## 7. 현재 iOS 상태 vs 목표

| 영역 | 현재 | Phase A 목표 |
|---|---|---|
| Voice Recording | ✅ 완료 | 유지 |
| Live Activity | ✅ 완료 | 유지 |
| H3-A 피드백 UI | ✅ 완료 | 승인 UI로 확장 |
| APNs 등록 | ✅ 완료 | 유지 |
| Command Input | ❌ | **신규** |
| Approval View | ❌ (피드백만) | **신규** |
| Agent Dashboard | ⚠️ 기본 | **확장** |
| Lifelog Viewer | ❌ (Phase 2) | Phase B 이후 |

## 8. 핵심 파일 예상 (iOS)

```
SonlifeApp/
  Features/
    Command/
      CommandInputView.swift          # 신규
      CommandViewModel.swift          # 신규
      PlanPreviewView.swift           # 신규
    Approval/
      ApprovalView.swift              # 신규 (H3-A 패턴 확장)
      ApprovalViewModel.swift         # 신규
      DiffView.swift                  # Phase B
      EmailDraftPreview.swift         # 신규
    Dashboard/
      AgentDashboardView.swift        # 확장
      SessionDetailView.swift         # 신규
      BudgetView.swift                # 신규
    Feedback/                         # 기존 H3-A
    Recording/                        # 기존
  Networking/
    CommandAPI.swift                  # 신규
    SessionsAPI.swift                 # 신규
    ApprovalAPI.swift                 # 신규
  Notifications/
    ApprovalNotificationHandler.swift # 신규
    NotificationCategories.swift      # 확장
  Models/
    AgentSession.swift                # 신규
    ApprovalToken.swift               # 신규
    Plan.swift                        # 신규
```

## 9. Open Questions (iOS 관점)

1. **명령 입력 UX**: 텍스트 vs 음성 vs 둘 다? 초기엔 텍스트가 안전.
2. **승인 대기 중 앱 동작**: 사용자가 앱을 강제 종료하면? (서버는 suspended 상태 유지, 다음 실행 시 배지로 알림)
3. **Diff view 구현**: 코드 diff를 제대로 보여주려면 SwiftUI에서 syntax highlighting 필요 — Highlightr 같은 라이브러리 도입?
4. **Live Activity로 실행 중 상태 표시?**: 긴 작업(코드 작업 5분+)은 Dynamic Island에 표시하면 좋을 듯.
5. **Widget 통합**: 홈 화면 위젯에 "오늘의 pending approvals" 표시할지?
6. **macOS 지원?**: 데스크톱에서 작업할 때 승인이 더 편할 수 있음. SwiftUI multiplatform.

## 10. Non-Goals

- ❌ iOS에서 LLM 직접 호출
- ❌ iOS에서 에이전트 실행 로직 구현
- ❌ 복잡한 로컬 DB (서버가 진실의 근원)
- ❌ 오프라인 모드로 새 명령 발행 (조회만 캐시)
- ❌ 에이전트가 iOS에 **자동으로** 무언가를 쓰기 (항상 사용자가 승인 후)

## 11. 참고 자료

- [Claude Code 하네스 엔지니어링 분석](https://plateer.atlassian.net/wiki/spaces/EC/pages/1541144577/Claude+Code) — 12계층 분석 문서
- [sonlife 백엔드 VISION 문서](https://github.com/SonAIengine/sonlife/blob/main/docs/AGENT-SYSTEM-VISION.md) — 서버 구현 상세
- [H3-A APNs Feedback 가이드](./H3-A-APNs-Feedback.md) — 기존 승인 UI 패턴
- [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview) — Anthropic 공식 SDK (서버 CodingAgent 엔진)

---

**이 문서는 초안이다.** 백엔드 Phase A와 iOS Phase A는 병행 진행 — 서버 API 계약을 먼저 합의한 뒤 양쪽 구현 시작.
