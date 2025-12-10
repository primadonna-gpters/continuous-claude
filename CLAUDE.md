# CLAUDE.md

Continuous Claude 프로젝트 개발 가이드입니다.

## Language

코드 작성을 제외한 모든 내용은 한국어로 작성합니다.

---

## Quick Reference

```bash
# 단일 에이전트 실행
./continuous_claude.sh -p "your task" -m 5

# 멀티 에이전트 스웜 실행
./continuous_claude.sh swarm -p "build feature" -m pipeline

# 대시보드 시작
./continuous_claude.sh dashboard start

# 테스트 실행
bats tests/
```

---

## 1. 프로젝트 개요

**Continuous Claude**는 Claude Code CLI를 자동화하여 반복적인 개발 작업을 수행하는 도구입니다.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **Continuous Loop** | Claude Code를 반복 실행하여 점진적으로 작업 완료 |
| **Multi-Agent Swarm** | 여러 에이전트(planner, developer, tester, reviewer)가 협업 |
| **Auto PR Management** | 자동 브랜치 생성, PR 생성, CI 대기 |
| **Failure Learning** | 실패 패턴을 학습하여 다음 시도에 적용 |
| **Real-time Dashboard** | 에이전트 상태 실시간 모니터링 |

### 버전

- **v1.x**: 단일 에이전트 continuous loop
- **v2.0**: 멀티 에이전트 시스템 (swarm)

---

## 2. 프로젝트 구조

```
continuous-claude/
├── continuous_claude.sh      # 메인 CLI 스크립트
├── install.sh                # 설치 스크립트
├── lib/                      # 모듈 라이브러리
│   ├── coordination.sh       # 스웜 조정 엔진 (핵심)
│   ├── orchestrator.sh       # 상태 관리
│   ├── messaging.sh          # 에이전트 간 메시징
│   ├── personas.sh           # 페르소나 로딩
│   ├── worktrees.sh          # Git worktree 관리
│   ├── conflicts.sh          # 충돌 감지/해결
│   ├── learning.sh           # 실패 학습 시스템
│   ├── review.sh             # 코드 리뷰 자동화
│   └── dashboard.sh          # 대시보드 서버
├── personas/                 # 에이전트 페르소나 정의
│   ├── planner.yaml          # 기획자
│   ├── developer.yaml        # 개발자
│   ├── tester.yaml           # 테스터
│   ├── reviewer.yaml         # 리뷰어
│   ├── documenter.yaml       # 문서 작성자
│   └── security.yaml         # 보안 분석가
├── dashboard/                # 대시보드 UI
│   ├── backend/              # FastAPI 백엔드
│   └── frontend/             # Svelte 프론트엔드
├── tests/                    # Bats 테스트
├── docs/                     # 문서
├── README.md                 # 사용자 문서
└── PLAN_MULTI_AGENT_SYSTEM.md # 설계 문서
```

---

## 3. 핵심 모듈 설명

### 3.1 coordination.sh (핵심)

멀티 에이전트 조정 엔진. 스웜 모드의 핵심 로직.

**주요 함수:**

| 함수 | 설명 |
|------|------|
| `run_swarm()` | 스웜 시작점, 세션 ID 생성 |
| `run_agent_pipeline()` | 파이프라인 워크플로우 실행 |
| `execute_agent()` | 개별 에이전트 실행 (Claude 호출) |
| `create_draft_pr()` | Draft PR 생성 |
| `push_agent_changes()` | 에이전트 변경사항 Push |
| `build_agent_prompt()` | 역할별 프롬프트 생성 |

**워크플로우:**
```
브랜치 생성 → Draft PR → planner → [developer → tester → (버그 루프)]
                                   ↓
                              reviewer
                                   ↓
                   (승인) → PR Ready → 머지
                   (변경요청) → 다시 developer로 ↩
```

**주요 시그널:**
- `AGENT_TASK_COMPLETE` - 에이전트 작업 완료
- `BUGS_FOUND` - 테스터가 버그 발견 → developer로 회귀
- `REVIEW_APPROVED` - 리뷰어 승인 → PR Ready
- `REVIEW_CHANGES_REQUESTED` - 리뷰어 변경 요청 → developer로 회귀

### 3.2 orchestrator.sh

에이전트 상태 관리 및 태스크 큐.

**주요 함수:**
- `init_swarm()` - 스웜 초기화
- `register_agent()` / `update_agent_state()` - 에이전트 상태 관리
- `get_swarm_status_json()` - 상태 조회

### 3.3 messaging.sh

에이전트 간 비동기 메시징 시스템.

**주요 함수:**
- `send_message()` - 메시지 전송
- `read_messages()` - 메시지 수신
- `get_unread_count()` - 읽지 않은 메시지 수

### 3.4 personas.sh

YAML 페르소나 정의 로딩 및 관리.

**주요 함수:**
- `load_persona()` - 페르소나 로드
- `get_persona_*()` - 페르소나 속성 조회

---

## 4. CLI 명령어

### 4.1 단일 에이전트 모드

```bash
continuous-claude -p "prompt" -m <max-runs> [options]

# 옵션
-m, --max-runs <n>          # 최대 반복 횟수
--max-cost <dollars>        # 최대 비용 (USD)
--max-duration <duration>   # 최대 시간 (예: "2h", "30m")
--disable-commits           # 커밋/PR 비활성화
--worktree <name>           # Git worktree에서 실행
```

### 4.2 멀티 에이전트 스웜

```bash
continuous-claude swarm -p "prompt" [options]

# 옵션
-m, --mode <mode>           # pipeline | parallel | adaptive
-a, --agents <list>         # 에이전트 목록 (기본: planner developer tester reviewer)
-r, --max-runs <n>          # 에이전트당 최대 반복
-v, --verbose               # 실시간 출력 스트리밍
--auto-merge                # 리뷰 승인 시 자동 머지
```

### 4.3 기타 명령어

```bash
# 대시보드
continuous-claude dashboard start [port]
continuous-claude dashboard stop
continuous-claude dashboard status

# 학습 시스템
continuous-claude learn insights
continuous-claude learn failures

# 에이전트 관리
continuous-claude agents list
continuous-claude agents info <persona_id>
```

---

## 5. 개발 컨벤션

### 5.1 Bash 스타일

```bash
# 함수 정의
function_name() {
    local var="$1"           # 지역 변수 사용
    local result=""

    # 에러 처리
    if [[ -z "$var" ]]; then
        echo "Error: var is required" >&2
        return 1
    fi

    # stdout은 반환값, stderr는 로그
    echo "Processing..." >&2
    echo "$result"  # 반환값
}

# 변수 네이밍
local my_variable=""         # snake_case
GLOBAL_CONSTANT=""           # UPPER_SNAKE_CASE

# 조건문
if [[ "$var" == "value" ]]; then
    # [[ ]] 사용 (POSIX [ ] 대신)
fi

# 배열
local -a my_array=()
my_array+=("item")
```

### 5.2 파일 구조

```bash
#!/usr/bin/env bash
# =============================================================================
# module_name.sh - 모듈 설명
# =============================================================================
# 상세 설명
# =============================================================================

# 설정
SOME_CONFIG="${SOME_CONFIG:-default}"

# =============================================================================
# 함수 그룹 1
# =============================================================================

# 함수 설명
# Usage: function_name <arg1> [arg2]
# Returns: 설명
function_name() {
    ...
}
```

### 5.3 에러 처리

```bash
# stderr로 에러 출력
echo "❌ Error message" >&2
return 1

# 명령어 실패 캡처
if ! output=$(some_command 2>&1); then
    echo "Failed: $output" >&2
    return 1
fi
```

### 5.4 시그널 규칙

에이전트가 출력하는 시그널:

| 시그널 | 의미 |
|--------|------|
| `AGENT_TASK_COMPLETE` | 현재 에이전트 작업 완료 |
| `PROJECT_COMPLETE` | 전체 프로젝트 완료 |
| `BUGS_FOUND` | 테스터가 버그 발견 |
| `APPROVED_FOR_MERGE` | 리뷰어가 승인 |

---

## 6. 페르소나 정의

### 6.1 YAML 스키마

```yaml
persona:
  id: developer              # 고유 ID
  name: "Developer Agent"    # 표시 이름
  emoji: "🧑‍💻"               # 이모지

  role: |                    # 역할 설명
    You are a skilled developer...

  responsibilities:          # 책임 목록
    - Implement features
    - Fix bugs

  constraints:               # 제약 조건
    - Do not write tests
    - Leave reviews for Reviewer

  communication:             # 메시징 설정
    listens_to:
      - reviewer.feedback
    publishes:
      - developer.feature_complete

  tools:                     # 허용/거부 도구
    allowed:
      - Read
      - Write
      - Edit
    denied:
      - Bash(git push)

  completion_signals:        # 완료 시그널
    ready_for_test: "READY_FOR_TESTING"
```

### 6.2 기본 페르소나

| ID | 역할 | 다음 단계 |
|----|------|----------|
| `planner` | 요구사항 분석, 계획 수립 | developer |
| `developer` | 코드 구현 | tester |
| `tester` | 테스트 작성/실행 | reviewer (통과) / developer (실패) |
| `reviewer` | 코드 리뷰, PR 승인 | merge (승인) / developer (변경요청) |

**리뷰어 시그널:**
- `REVIEW_APPROVED` - 코드 승인, PR Ready로 마킹
- `REVIEW_CHANGES_REQUESTED` - 변경 필요, developer로 회귀

---

## 7. 상태 관리

### 7.1 디렉토리 구조

```
.continuous-claude/
├── state/
│   ├── session.json        # 세션 정보
│   ├── agents.json         # 에이전트 상태
│   ├── tasks.json          # 태스크 큐
│   └── activity.log        # 실시간 활동 로그 (대시보드용)
├── messages/
│   ├── inbox/<agent>/      # 수신 메시지
│   └── outbox/             # 발신 대기
└── learning/
    ├── failures.json       # 실패 기록
    └── insights.json       # 학습된 인사이트
```

### 7.2 세션 ID 형식

```
YYYYMMDD-HHMMSS-PID-RANDOM
예: 20251210-143025-12345-a1b2
```

---

## 8. 테스트

### 8.1 Bats 테스트 실행

```bash
# 전체 테스트
bats tests/

# 특정 테스트 파일
bats tests/test_continuous_claude.bats
```

### 8.2 테스트 작성

```bash
#!/usr/bin/env bats

@test "function should work" {
    result=$(some_function "input")
    [ "$result" == "expected" ]
}

@test "function should fail on invalid input" {
    run some_function ""
    [ "$status" -eq 1 ]
}
```

---

## 9. 디버깅

### 9.1 Verbose 모드

```bash
# 실시간 Claude 출력 스트리밍
continuous-claude swarm -p "task" -v
```

### 9.2 상태 확인

```bash
# 스웜 상태 조회
./lib/coordination.sh status

# 대시보드 상태
./lib/dashboard.sh status

# 에이전트 상태
cat .continuous-claude/state/agents.json | jq .
```

### 9.3 로그 확인

```bash
# 대시보드 로그
tail -f /tmp/continuous-claude-dashboard.log

# 에이전트 메시지
ls .continuous-claude/messages/inbox/
```

---

## 10. 주의사항

### 10.1 금지 사항

- `--dangerously-skip-permissions` 외부 노출 금지
- 민감 정보 (API 키 등) 코드에 포함 금지
- `git push --force` 사용 금지
- 테스트 없이 main 브랜치 직접 수정 금지

### 10.2 모범 사례

- 모든 함수에 Usage 주석 작성
- stderr는 로그, stdout은 반환값으로 사용
- 지역 변수는 `local` 키워드 사용
- 에러 발생 시 명확한 메시지와 함께 `return 1`

### 10.3 호환성

- Bash 3.2+ 호환 (macOS 기본)
- GNU/BSD 도구 호환 고려 (sed, grep 등)
- jq 필수 의존성

---

## 11. 릴리스 프로세스

### 11.1 버전 업데이트

1. `continuous_claude.sh`의 `VERSION` 변경
2. `CHANGELOG.md` 업데이트
3. Git 태그 생성: `git tag v2.x.x`
4. Push: `git push origin main --tags`

### 11.2 체크섬 업데이트

```bash
sha256sum continuous_claude.sh > continuous_claude.sh.sha256
```

---

## 12. 참조 문서

- [README.md](./README.md) - 사용자 문서
- [PLAN_MULTI_AGENT_SYSTEM.md](./PLAN_MULTI_AGENT_SYSTEM.md) - 설계 문서
- [CHANGELOG.md](./CHANGELOG.md) - 변경 이력
