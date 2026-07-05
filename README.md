# Hermes Google Antigravity Provider for Windows

Windows Hermes에서 Google Antigravity OAuth provider를 다시 적용하기 위한 최소 패키지입니다.

이 패키지는 Hermes 코어 저장소에 영구 패치를 병합하지 않습니다. 업데이트나 재설치 후 다시 복사할 수 있는 작은 런타임 레이어를 설치합니다.

## 하는 일

- `google-antigravity` model provider metadata 설치
- Antigravity OAuth/runtime adapter 설치
- 현재 Windows Hermes에 없는 Cloud Code 호환 파일 설치
- `sitecustomize.py` import hook 설치
- `agy.exe`에서 OAuth client id/secret을 추출해 private cache 생성
- `hermes auth add google-antigravity`, `hermes model`, runtime provider, `/agyquota` 연결

## 빠른 설치

PowerShell에서 이 폴더로 이동한 뒤 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\install-windows.ps1
```

상태 확인:

```powershell
.\scripts\install-windows.ps1 -Check
```

로그인:

```powershell
hermes auth add google-antigravity
```

또는:

```powershell
hermes model
```

에서 `Google Antigravity`를 선택합니다.

## 테스트

```powershell
hermes chat --provider google-antigravity -m gemini-3.5-flash-high -q "OK"
hermes chat --provider google-antigravity -m claude-opus-4-6 -q "OK"
hermes chat --provider google-antigravity -m gpt-oss-120b -q "OK"
```

## 업데이트 / 재설치 후

Hermes 업데이트 또는 `%LOCALAPPDATA%\hermes\hermes-agent` 재설치 후 다시 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\install-windows.ps1
```

OAuth 토큰은 보통 아래에 남아 있으므로 Hermes 코드 재설치만으로는 다시 로그인하지 않아도 될 수 있습니다.

```text
%LOCALAPPDATA%\hermes\auth\google_antigravity.json
%USERPROFILE%\.gemini\antigravity-cli\antigravity-oauth-token
```

## 로그아웃

Hermes credential pool 항목만 지우려면:

```powershell
hermes auth remove google-antigravity 1
```

Antigravity OAuth 파일까지 지우려면:

```powershell
.\scripts\logout-antigravity-windows.ps1
```

`google_antigravity_client.json`은 access/refresh token이 아니라 `agy.exe`에서 추출한 OAuth client cache입니다. 로그아웃 대상이 아닙니다.

## 기본 provider에서 빼기

Antigravity를 기본 provider에서 빼고 Hermes 기본 Nous provider로 되돌리려면:

```powershell
.\scripts\disable-antigravity-windows.ps1
```

## 파일 구조

```text
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

scripts/
  install-windows.ps1
  logout-antigravity-windows.ps1
  disable-antigravity-windows.ps1
  sitecustomize_hook.py
```

## 제거한 레거시 구성

이 Windows 패키지에서는 아래 원본 저장소 구성요소를 유지하지 않습니다.

- Linux/macOS `install.sh`, `repair.sh`, `post-merge-hook.sh`
- 오래된 `hermes-agent-antigravity-core.patch`
- 원본 repository 테스트 파일
- 별도 image generation provider
- 중복 Windows guide 문서
- standalone plan status/check scripts

필요하면 `/agyquota` 명령으로 Antigravity quota/status를 확인합니다.

## 주의

이 통합은 비공식 Antigravity OAuth 연동입니다. Google/Antigravity 정책 변경, `agy` binary 변경, Hermes 내부 API 변경에 영향을 받을 수 있습니다.
