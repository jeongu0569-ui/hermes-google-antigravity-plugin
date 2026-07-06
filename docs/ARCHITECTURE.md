# Architecture Guide

이 문서는 Hermes나 provider plugin 구조에 익숙하지 않은 개발자가 이 프로젝트를 읽을 수 있도록, 전체 동작 원리와 파일별 역할을 설명합니다.

## 한 줄 요약

이 프로젝트는 Hermes에 원래 없는 `google-antigravity` provider를 추가하기 위해 만든 작은 런타임 확장 패키지입니다.

설치 스크립트는 공통 Python 파일을 Hermes 설치본에 복사하고, `sitecustomize.py` hook을 통해 Hermes가 실행될 때 필요한 registry와 runtime resolver만 동적으로 보강합니다.

## 큰 그림

Hermes가 모델을 호출할 때는 대략 다음 순서로 움직입니다.

```text
사용자 요청
→ Hermes가 provider 이름을 해석
→ 인증 정보/API key/OAuth token 준비
→ provider에 맞는 client 생성
→ messages/tools를 provider API 형식으로 변환
→ HTTP 요청
→ 응답을 Hermes/OpenAI 호환 형식으로 변환
```

이 프로젝트는 이 흐름 중 세 곳에 들어갑니다.

1. `google-antigravity`라는 provider 이름을 Hermes가 알 수 있게 등록합니다.
2. Google Antigravity OAuth token을 읽고 refresh할 수 있게 합니다.
3. Hermes의 OpenAI Chat Completions 형태 요청을 Google Cloud Code PA 내부 API 형태로 바꿔 보냅니다.

## 왜 hook이 필요한가

`common/plugins/model-providers/google-antigravity`만 보면 일반 플러그인처럼 보입니다. 이 provider profile은 이름, 표시명, fallback model 목록 같은 metadata를 등록합니다.

하지만 현재 Hermes plugin hook만으로는 아래 기능을 완전히 추가하기 어렵습니다.

- 새로운 OAuth resolver 등록
- `oauth_external` provider의 token 해석 방식 추가
- `cloudcode-pa://antigravity` 같은 marker URL을 실제 client로 연결
- `/model` picker와 WebUI model list에 provider 노출
- `/agyquota` 같은 slash command 추가

그래서 `common/sitecustomize_hook.py`가 필요합니다.

Python은 시작할 때 import path에 `sitecustomize.py`가 있으면 자동으로 import합니다. 설치 스크립트는 Hermes virtualenv에 이 파일을 설치합니다. 그러면 Hermes가 실행될 때 `sitecustomize.py`가 먼저 실행되고, Hermes 내부 모듈이 import되는 순간 필요한 patch를 적용할 수 있습니다.

중요한 점은 Hermes 원본 파일을 직접 수정하지 않는다는 것입니다. 업데이트 후 다시 설치 스크립트를 실행하면 같은 런타임 레이어를 다시 얹을 수 있습니다.

## 요청 흐름

Antigravity를 명시적으로 사용할 때의 흐름은 다음과 같습니다.

```text
hermes chat --provider google-antigravity ...
→ hermes_cli.runtime_provider.resolve_runtime_provider()
→ antigravity_provider_patch가 google-antigravity 별칭인지 확인
→ agent.google_antigravity_oauth에서 access token 확보
→ agent.google_antigravity_adapter.GoogleAntigravityClient 생성
→ OpenAI-style messages/tools를 Cloud Code PA request로 변환
→ https://cloudcode-pa.googleapis.com/v1internal:generateContent 호출
→ 응답을 OpenAI-compatible response로 변환
→ Hermes가 사용자에게 출력
```

Antigravity가 아닌 provider는 건드리지 않습니다.

```text
custom:ollama-local
codex 계열 provider
openai / anthropic / nous
auto / None
기타 Hermes runtime 특수 provider
→ Hermes 원래 resolver로 그대로 전달
```

이렇게 한 이유는 provider resolver는 Hermes의 중심부라서, Antigravity가 아닌 provider까지 가로채면 예상치 못한 충돌이 생길 수 있기 때문입니다. 실제로 `custom:ollama-local`이 `custom_providers` 설정으로 가야 하는데 Antigravity wrapper가 먼저 `resolve_provider()`를 호출해서 `Unknown provider`가 난 문제가 있었습니다.

현재 설계는 더 보수적입니다.

```text
requested가 google-antigravity / antigravity / antigravity-oauth일 때만 직접 처리
그 외에는 즉시 original resolver로 반환
```

## 디렉터리 구조

```text
common/
  agent/
  patches/
  plugins/
  sitecustomize_hook.py

mac/
  install.sh
  logout-antigravity.sh
  disable-antigravity.sh

windows/
  install.ps1
  logout-antigravity.ps1
  disable-antigravity.ps1
```

`common/`은 운영체제와 무관하게 같은 Python 런타임입니다. `mac/`과 `windows/`는 Hermes 설치 위치, virtualenv 경로, shell 문법만 다르기 때문에 분리되어 있습니다.

## 파일별 역할

### `common/sitecustomize_hook.py`

Hermes virtualenv에 `sitecustomize.py`로 설치되는 import hook입니다.

역할:

- Hermes 내부 모듈이 import되는 시점을 감지합니다.
- `common/patches/antigravity_provider_patch.py`를 불러옵니다.
- provider registry, auth registry, runtime provider, model picker, WebUI config, slash command 쪽 patch를 적용합니다.

이 파일이 직접 비즈니스 로직을 많이 갖고 있지는 않습니다. “언제 patch를 적용할지”를 담당하는 부트스트랩 코드입니다.

### `common/patches/antigravity_provider_patch.py`

Hermes 내부에 Antigravity provider를 연결하는 핵심 patch 파일입니다.

주요 기능:

- `HERMES_OVERLAYS`에 `google-antigravity` 추가
- auth registry에 `google-antigravity` 추가
- Antigravity OAuth credential resolver 추가
- runtime provider resolver에 Antigravity 처리 추가
- agent runtime client factory에 `GoogleAntigravityClient` 연결
- `/model` picker에 Antigravity model 목록 추가
- WebUI `/api/models` 응답에 Antigravity 추가
- `/agyquota` slash command 등록

설계상 가장 중요한 원칙은 “Antigravity 요청만 처리하고 나머지는 Hermes 원래 로직으로 돌려보낸다”입니다.

### `common/plugins/model-providers/google-antigravity/__init__.py`

Hermes provider profile metadata입니다.

역할:

- provider 이름: `google-antigravity`
- aliases: `antigravity`, `antigravity-oauth`
- 표시 이름: `Google Antigravity (OAuth)`
- marker base URL: `cloudcode-pa://antigravity`
- 인증 방식: `oauth_external`
- fallback model 목록 등록
- Gemini Pro 계열 high/low suffix를 `thinking_config`로 변환

이 파일만으로는 실제 HTTP 요청이 동작하지 않습니다. Hermes에 “이런 provider가 있다”는 정보를 제공하는 역할에 가깝습니다.

### `common/plugins/model-providers/google-antigravity/plugin.yaml`

플러그인 manifest metadata입니다.

역할:

- plugin 이름
- kind
- version
- 설명
- provider id
- author/license

### `common/agent/google_antigravity_oauth.py`

Antigravity OAuth 전용 코드입니다.

역할:

- `agy` CLI 바이너리에서 OAuth client id/secret 추출
- `HERMES_ANTIGRAVITY_CLIENT_ID`, `HERMES_ANTIGRAVITY_CLIENT_SECRET` 환경변수 지원
- client cache 저장: `~/.hermes/auth/google_antigravity_client.json`
- access/refresh token 저장: `~/.hermes/auth/google_antigravity.json`
- Antigravity CLI token mirror 경로 지원: `~/.gemini/antigravity-cli/...`
- Google OAuth PKCE login flow 실행
- token refresh
- account별 Cloud Code project id 저장

client id/secret은 source code에 직접 넣지 않고 `agy`에서 추출하거나 환경변수로 받습니다. 그래서 repository에 민감한 token이 들어가지 않습니다.

### `common/agent/google_antigravity_adapter.py`

Antigravity 요청을 실제로 보내는 OpenAI-compatible client입니다.

역할:

- Hermes/OpenAI 스타일 `chat.completions.create(...)` 인터페이스 제공
- 요청마다 OAuth access token 확보
- `loadCodeAssist`로 project/plan 정보를 확인
- Hermes messages/tools를 Cloud Code PA request로 변환
- Antigravity model label을 backend model id로 매핑
- thinking tier 변환
- Claude/GPT-OSS tool schema 보정
- Claude bridge용 request metadata 보정
- Google One AI credit 사용 여부 결정
- streaming SSE 응답 처리
- 응답을 OpenAI-compatible 형태로 변환

즉 “Hermes가 아는 모양”과 “Google Antigravity backend가 원하는 모양” 사이의 번역기입니다.

Claude 계열 모델은 Gemini 계열 endpoint wrapper를 통과하지만, 실제 bridge는 Anthropic tool validator와 다른 request metadata 규칙을 함께 사용합니다. 그래서 일반 Gemini 요청처럼 `VALIDATED` tool mode, `generationConfig`, provider-level `sessionId`를 그대로 보내면 `INVALID_ARGUMENT`가 발생할 수 있습니다. 이때 adapter의 fallback retry가 마지막 사용자 메시지 중심으로 줄어들면 Hermes DB에는 `history=2` 이상이 있어도 provider로 전달되는 transcript가 짧아져, 같은 세션의 이전 발화를 기억하지 못하는 것처럼 보일 수 있습니다.

현재 보정은 Claude 요청에만 적용됩니다.

- Hermes tool declarations는 유지합니다.
- function calling mode는 `AUTO`로 보냅니다.
- Claude 요청에서는 `generationConfig`와 provider-level `sessionId`를 제거합니다.
- Hermes 세션 저장과 resume은 Hermes 서버가 계속 담당합니다.

검증 기준은 같은 Hermes session에서 “안녕 내 이름은 ...” 다음 “내 이름이 뭐라고?”를 물었을 때 이름을 기억하고, 로그에 `Antigravity stream HTTP 400 diagnostics` fallback이 새로 발생하지 않는 것입니다.

### `common/agent/gemini_cloudcode_adapter.py`

Google Cloud Code PA용 공통 변환기입니다.

역할:

- OpenAI `messages[]`를 Gemini `contents[]`로 변환
- OpenAI `tools[]`를 Gemini `functionDeclarations`로 변환
- Gemini response를 OpenAI-style response로 변환
- streaming SSE event를 Hermes가 이해할 수 있는 chunk로 변환

Antigravity adapter는 이 파일의 변환 로직을 많이 재사용합니다.

### `common/agent/google_code_assist.py`

Cloud Code Assist control-plane API client입니다.

역할:

- `loadCodeAssist` 호출
- account tier, project id, quota 관련 정보 확인
- 필요한 경우 onboarding 요청
- quota endpoint 호출

모델 호출 자체보다는 “이 계정이 어떤 project/tier로 Cloud Code PA를 쓸 수 있는지” 확인하는 역할입니다.

### `common/agent/google_oauth.py`

Hermes 버전에 따라 `agent.google_oauth`가 없을 수 있어서 넣어둔 호환용 OAuth helper입니다.

역할:

- PKCE helper
- credential file read/write
- token refresh
- Google OAuth token exchange
- project id 저장

`google_antigravity_oauth.py`는 이 공통 helper의 설정값을 잠시 Antigravity용으로 바꿔서 재사용합니다. OAuth 코드를 완전히 복사하지 않기 위한 설계입니다.

### `common/agent/antigravity_quota_grpc.py`

Antigravity quota/status를 gRPC endpoint에서 읽기 위한 helper입니다.

역할:

- Antigravity CLI에서 쓰는 것으로 보이는 quota gRPC method 호출
- base/extended quota bucket 파싱
- `grpcio`가 없거나 token이 거부되면 caller가 fallback할 수 있게 실패를 부드럽게 처리

### `common/agent/antigravity_quota_report.py`

`/agyquota`에서 보여줄 텍스트 report를 만듭니다.

역할:

- OAuth token 확보
- project/plan 정보 수집
- gRPC quota 정보 수집
- 사람이 읽기 쉬운 quota/status 문자열 생성

### `common/agent/antigravity_stream_grpc.py`

긴 대화 context를 다룰 때 Antigravity request에 context compression 관련 설정을 넣는 helper입니다.

역할:

- 모델별 context window 기준값 관리
- sliding-window compression config 생성
- request body에 compression 설정 주입

### `mac/install.sh`

macOS 설치 스크립트입니다.

역할:

- 기본 Hermes home을 `~/.hermes`로 사용
- `venv/bin/python`, `venv/bin/hermes` 탐색
- `common/`의 provider metadata와 agent runtime 파일 복사
- patch 파일을 `~/.hermes/patches`에 복사
- `sitecustomize.py`를 Hermes virtualenv에 설치
- `agy`에서 OAuth client cache 생성
- 설치 상태 검증, login, smoke test 옵션 제공

### `mac/logout-antigravity.sh`

macOS token cleanup 스크립트입니다.

역할:

- Hermes Antigravity OAuth credential 삭제
- 필요하면 Antigravity CLI mirror token도 삭제
- client cache는 삭제하지 않음

### `mac/disable-antigravity.sh`

macOS에서 기본 provider를 Antigravity가 아닌 fallback provider로 돌리는 스크립트입니다.

역할:

- `~/.hermes/config.yaml` 백업
- `model.provider`, `model.default`, `model.base_url` 수정

### `windows/install.ps1`

Windows 설치 스크립트입니다.

역할은 `mac/install.sh`와 거의 같습니다. 차이는 경로입니다.

- 기본 Hermes home: `%LOCALAPPDATA%\hermes`
- Python: `venv\Scripts\python.exe`
- Hermes CLI: `venv\Scripts\hermes.exe`
- site-packages: `venv\Lib\site-packages`

### `windows/logout-antigravity.ps1`

Windows token cleanup 스크립트입니다.

### `windows/disable-antigravity.ps1`

Windows에서 기본 provider를 fallback provider로 돌리는 스크립트입니다.

## 왜 `common/`, `mac/`, `windows/`로 나눴나

Python 런타임 로직은 Windows와 macOS에서 거의 같습니다.

다른 부분은 주로 설치 경로와 shell 문법입니다.

- Windows는 PowerShell, `%LOCALAPPDATA%`, `Scripts\python.exe`
- macOS는 bash, `~/.hermes`, `bin/python`

그래서 공통 로직을 중복하지 않기 위해 `common/`에 두고, 설치/관리 스크립트만 OS별 폴더로 분리했습니다.

## 왜 Hermes 원본을 직접 수정하지 않나

Hermes는 업데이트되거나 재설치될 수 있습니다. 원본 파일을 직접 수정하면:

- 업데이트 때 변경이 사라질 수 있습니다.
- 충돌 해결이 어렵습니다.
- 어떤 부분이 공식 Hermes 코드이고 어떤 부분이 Antigravity patch인지 구분하기 어렵습니다.

이 프로젝트는 대신 “복사 가능한 작은 런타임 레이어”를 설치합니다.

장점:

- 재설치가 쉽습니다.
- 원본 Hermes repo를 깨끗하게 유지할 수 있습니다.
- 문제가 생기면 `~/.hermes/patches/antigravity_provider_patch.py` 또는 `sitecustomize.py`를 제거해 비활성화하기 쉽습니다.

단점:

- Hermes 내부 API가 바뀌면 patch가 깨질 수 있습니다.
- import hook과 monkey patch는 일반 플러그인보다 디버깅이 어렵습니다.
- 그래서 patch는 가능한 좁은 범위만 건드려야 합니다.

## 설계상 주의할 점

### Provider resolver는 넓게 건드리면 위험합니다

Hermes에는 기본 provider뿐 아니라 custom provider, profile provider, runtime-only provider가 있을 수 있습니다.

그래서 Antigravity patch는 다음처럼 동작해야 합니다.

```text
Antigravity 별칭이면 직접 처리
그 외에는 original resolver로 즉시 위임
```

이 원칙을 깨면 `custom:ollama-local` 같은 provider가 정상 설정을 갖고 있어도 중간에서 실패할 수 있습니다.

### OAuth client cache와 OAuth token은 다릅니다

`google_antigravity_client.json`은 `agy`에서 추출한 OAuth client id/secret cache입니다. access token이나 refresh token이 아닙니다.

실제 로그인 token은 `google_antigravity.json`과 Antigravity CLI token mirror 경로에 저장됩니다.

그래서 logout 스크립트는 token을 지우지만 client cache는 지우지 않습니다.

### `cloudcode-pa://antigravity`는 실제 URL이 아닙니다

이 값은 Hermes 내부에서 “이 provider는 일반 OpenAI HTTP endpoint가 아니라 Antigravity adapter로 보내야 한다”는 marker입니다.

실제 HTTP 요청은 adapter가 `https://cloudcode-pa.googleapis.com/v1internal:generateContent`로 보냅니다.

## 디버깅 팁

설치 상태 확인:

```bash
./mac/install.sh --check
```

Windows:

```powershell
.\windows\install.ps1 -Check
```

custom provider가 원래 Hermes resolver를 타는지 확인:

```bash
HERMES_HOME="$HOME/.hermes" "$HOME/.hermes/hermes-agent/venv/bin/python" - <<'PY'
from hermes_cli.runtime_provider import resolve_runtime_provider
result = resolve_runtime_provider(
    requested="custom:ollama-local",
    target_model="gemma4:e2b-mlx",
)
print(result.get("provider"), result.get("base_url"), result.get("source"))
PY
```

정상 예:

```text
custom http://localhost:11434/v1 custom_provider:ollama local
```

## 유지보수 원칙

- Antigravity가 아닌 provider는 건드리지 않습니다.
- Hermes 내부 함수 signature가 바뀔 수 있으므로 patch 적용 전 가능한 signature를 확인합니다.
- 설치 스크립트는 공통 Python 파일을 복사만 하고, OS별 경로 차이만 처리합니다.
- token이나 secret은 repository에 저장하지 않습니다.
- README에는 사용법을, 이 문서에는 설계와 작동 원리를 적습니다.
