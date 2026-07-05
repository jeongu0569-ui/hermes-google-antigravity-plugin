# Hermes Google Antigravity Provider

Hermes에서 Google Antigravity OAuth provider를 다시 적용하기 위한 최소 패키지입니다.

이 패키지는 Hermes 코어 저장소에 영구 패치를 병합하지 않습니다. Windows/macOS별 설치 스크립트가 공통 런타임 파일을 Hermes 설치본에 복사하고, `sitecustomize.py` import hook으로 Hermes 내부 registry를 런타임에 패치합니다.

## 지원 플랫폼

- Windows: `windows/install.ps1`
- macOS: `mac/install.sh`

공통 Python 런타임, provider metadata, patch hook은 `common/` 아래에 있습니다.

## 하는 일

- `google-antigravity` model provider metadata 설치
- Antigravity OAuth/runtime adapter 설치
- Cloud Code PA 호환 파일 설치
- `sitecustomize.py` import hook 설치
- `agy` CLI에서 OAuth client id/secret을 추출해 private cache 생성
- `hermes auth add google-antigravity`, `hermes model`, runtime provider, `/agyquota` 연결

## macOS 설치

`agy` CLI를 설치하고 PATH에서 잡히는지 먼저 확인합니다.

```bash
which agy
```

이 폴더에서 실행합니다.

```bash
./mac/install.sh
```

상태 확인:

```bash
./mac/install.sh --check
```

로그인까지 이어서 실행하려면:

```bash
./mac/install.sh --login
```

Hermes home이 기본값 `~/.hermes`가 아니면:

```bash
./mac/install.sh --hermes-home /path/to/hermes
```

## Windows 설치

PowerShell에서 이 폴더로 이동한 뒤 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\windows\install.ps1
```

상태 확인:

```powershell
.\windows\install.ps1 -Check
```

로그인까지 이어서 실행하려면:

```powershell
.\windows\install.ps1 -Login
```

## 로그인

설치 후 직접 로그인:

```bash
hermes auth add google-antigravity
```

또는:

```bash
hermes model
```

에서 `Google Antigravity`를 선택합니다.

## 테스트

```bash
hermes chat --provider google-antigravity -m gemini-3.5-flash-high -q "OK"
hermes chat --provider google-antigravity -m claude-opus-4-6 -q "OK"
hermes chat --provider google-antigravity -m gpt-oss-120b -q "OK"
```

macOS 설치 스크립트에서 smoke test까지 실행하려면:

```bash
./mac/install.sh --smoke
```

Windows:

```powershell
.\windows\install.ps1 -Smoke
```

## 업데이트 / 재설치 후

Hermes 업데이트 또는 `hermes-agent` 재설치 후 다시 실행합니다.

macOS:

```bash
./mac/install.sh
```

Windows:

```powershell
.\windows\install.ps1
```

OAuth 토큰은 보통 아래에 남아 있으므로 Hermes 코드 재설치만으로는 다시 로그인하지 않아도 될 수 있습니다.

macOS:

```text
~/.hermes/auth/google_antigravity.json
~/.gemini/antigravity-cli/antigravity-oauth-token
```

Windows:

```text
%LOCALAPPDATA%\hermes\auth\google_antigravity.json
%USERPROFILE%\.gemini\antigravity-cli\antigravity-oauth-token
```

## 로그아웃

Hermes credential pool 항목만 지우려면:

```bash
hermes auth remove google-antigravity 1
```

Antigravity OAuth 파일까지 지우려면:

macOS:

```bash
./mac/logout-antigravity.sh
```

Windows:

```powershell
.\windows\logout-antigravity.ps1
```

`google_antigravity_client.json`은 access/refresh token이 아니라 `agy`에서 추출한 OAuth client cache입니다. 로그아웃 대상이 아닙니다.

## 기본 provider에서 빼기

Antigravity를 기본 provider에서 빼고 Hermes 기본 Nous provider로 되돌리려면:

macOS:

```bash
./mac/disable-antigravity.sh
```

Windows:

```powershell
.\windows\disable-antigravity.ps1
```

## 파일 구조

```text
common/
  agent/
    gemini_cloudcode_adapter.py
    google_code_assist.py
    google_oauth.py
    google_antigravity_adapter.py
    google_antigravity_oauth.py
    antigravity_quota_grpc.py
    antigravity_quota_report.py
    antigravity_stream_grpc.py
  patches/
    antigravity_provider_patch.py
  plugins/model-providers/google-antigravity/
    __init__.py
    plugin.yaml
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

## 자세한 작동 원리

파일별 역할, hook이 필요한 이유, provider resolver 설계 원칙은 [Architecture Guide](docs/ARCHITECTURE.md)에 정리되어 있습니다.

## 동작 요약

`common/plugins/model-providers/google-antigravity`는 Hermes provider profile을 등록합니다. 실제 OAuth resolver와 model client 연결은 아직 Hermes plugin hook만으로는 부족해서 `common/sitecustomize_hook.py`가 Hermes module import 시점에 `common/patches/antigravity_provider_patch.py`를 적용합니다.

요청 실행 시 Hermes는 `google-antigravity`를 `cloudcode-pa://antigravity` provider로 해석하고, `agent.google_antigravity_adapter.GoogleAntigravityClient`가 OpenAI Chat Completions 형태의 요청을 Google Cloud Code PA `v1internal:generateContent` / `streamGenerateContent` 요청으로 변환합니다.

`custom:*` provider는 Antigravity wrapper가 처리하지 않고 Hermes 원래 runtime resolver로 그대로 넘깁니다. 예를 들어 `custom:ollama-local` 같은 named custom provider는 `custom_providers` 설정의 `base_url`과 모델을 기존 Hermes 방식으로 해석합니다.

필요하면 `/agyquota` 명령으로 Antigravity quota/status를 확인합니다.

## 주의

이 통합은 비공식 Antigravity OAuth 연동입니다. Google/Antigravity 정책 변경, `agy` binary 변경, Hermes 내부 API 변경에 영향을 받을 수 있습니다.
