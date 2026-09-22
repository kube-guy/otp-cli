# otp

TOTP(RFC 6238) 코드를 생성하는 macOS CLI. 시크릿은 macOS Keychain 에 저장합니다.

```
$ otp gitlab
494564
10초 남음
```

의존성이 없는 단일 바이너리입니다.

## 설치

```sh
brew tap kube-guy/ai-usage-bar
brew trust --formula kube-guy/ai-usage-bar/otp
brew install otp
```

Homebrew 7.0 부터는 서드파티 tap 의 formula 를 쓰려면 `brew trust` 가 한 번 필요합니다.

## 사용

```sh
otp add gitlab                        # 시크릿을 화면에 표시하지 않고 입력받아 등록
otp add gitlab "otpauth://totp/..."   # QR 에서 얻은 URI 로 등록
otp gitlab                            # 현재 코드
otp gitlab --copy                     # 코드를 클립보드로
otp gitlab --watch                    # 남은 시간과 함께 갱신 표시
otp list                              # 등록된 이름
otp remove gitlab
otp selftest                          # RFC 6238 벡터로 자체 검증
```

## 단축키로 바로 입력하기

OTP 입력란에 커서를 두고 단축키(기본 `⌘⌥O`)를 누르면 코드가 바로 타이핑됩니다.
클립보드를 거치지 않으므로 코드가 클립보드 이력에 남지 않습니다.

```sh
otp default gitlab             # 단축키가 쓸 계정 지정 (등록이 하나뿐이면 생략 가능)
brew services start otp        # 로그인 시 자동으로 단축키 대기
```

처음 실행하면 **손쉬운 사용 권한**을 요청합니다. 시스템 설정 → 개인정보 보호 및 보안 →
손쉬운 사용 에서 `otp` 를 허용한 뒤 다시 실행하세요. 합성 키 입력을 보내려면 필요한 권한입니다.

단축키를 바꾸려면:

```sh
otp agent --hotkey "ctrl+shift+9"
```

수정키(cmd/opt/ctrl/shift) 를 최소 하나 포함해야 하고, 다른 앱이 이미 쓰는 조합이면 등록에 실패합니다.

> `brew upgrade` 로 새 버전을 설치하면 실행 파일 경로가 바뀌어 손쉬운 사용 권한을
> 다시 허용해야 할 수 있습니다. 시스템 설정에서 기존 `otp` 항목을 지우고 다시 추가하세요.

코드는 stdout 으로, 남은 시간 등 부가 정보는 stderr 로 나가므로 파이프로 넘겨도 깔끔합니다.

```sh
otp gitlab | pbcopy
CODE=$(otp gitlab)
```

## 시크릿 저장 위치

macOS Keychain 의 login keychain 에 generic password 로 저장합니다.

| 항목 | 값 |
|---|---|
| service | `otp-cli` |
| account | 등록한 이름 |
| 값 | `{"secret":"...","digits":6,"period":30,"algorithm":"SHA1"}` |

`security` 로 직접 확인할 수 있습니다.

```sh
security find-generic-password -s otp-cli -a gitlab
```

### 왜 Keychain 인가

TOTP 시크릿은 비밀번호와 동등한 등급입니다. 유출되면 2단계 인증이 무력화됩니다.
Keychain 은 디스크에 암호화 저장되고 로그인 세션에 묶이며 항목별 접근 제어가 걸립니다.
평문 파일이나 환경변수는 `ps`, 셸 히스토리, 크래시 로그, 백업으로 새어나갑니다.

### 읽기·쓰기를 `security` 명령으로 하는 이유

Security 프레임워크로 직접 항목을 만들면 서명되지 않은 이 바이너리가 접근 주체가 되는데,
재빌드할 때마다 동일성이 깨져 키체인 승인 창이 다시 뜹니다.
Apple 서명된 `/usr/bin/security` 를 신뢰 주체로 고정하면 한 번 허용한 뒤로는 묻지 않습니다.

목록 조회(`otp list`)만 Security 프레임워크를 씁니다. 계정 이름 속성만 읽고 비밀값은
요청하지 않으므로 승인 대상이 아닙니다.

## 검증

RFC 6238 Appendix B 테스트 벡터(SHA1/SHA256/SHA512 각 6건)와 Base32·URI 파싱 검사를
바이너리에 내장했습니다.

```sh
$ otp selftest
PASS  RFC 6238 SHA1 벡터 6건
...
12/12 통과
```

XCTest 는 전체 Xcode 에만 포함되어 Command Line Tools 환경에서는 쓸 수 없으므로,
검증을 바이너리 안에 두어 어디서든 같은 검사를 돌릴 수 있게 했습니다.

## 지원 범위

- TOTP 만 지원합니다. HOTP(카운터 기반) 는 지원하지 않습니다.
- 6~8 자리, SHA1/SHA256/SHA512, 임의 period 를 지원합니다. 대부분의 서비스는 기본값(6자리/30초/SHA1) 을 씁니다.

## 개발

```sh
swift build -c release
./.build/release/otp selftest
```

## 라이선스

MIT
