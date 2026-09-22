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
otp scan                              # 클립보드의 QR 이미지에서 등록
otp scan ~/Desktop/qr.png             # 저장한 QR 이미지에서 등록
otp add gitlab                        # 시크릿을 화면에 표시하지 않고 입력받아 등록
otp add gitlab "otpauth://totp/..."   # QR 에서 얻은 URI 로 등록
otp gitlab                            # 현재 코드
otp gitlab --copy                     # 코드를 클립보드로
otp gitlab --watch                    # 남은 시간과 함께 갱신 표시
otp list                              # 등록된 이름
otp rename gitlab gitlab-work         # 이름 변경 (설정·기본계정 지정 유지)
otp remove gitlab
otp selftest                          # RFC 6238 벡터로 자체 검증
```

## 기존 인증 앱에서 옮기기

인증 앱이 QR 로만 내보내는 경우, QR 을 캡처해 `otp scan` 으로 읽으면 됩니다.

```sh
# ⌃⌘⇧4 로 QR 영역을 클립보드에 캡처한 뒤
otp scan

# 또는 ⌘⇧4 로 파일에 저장한 뒤
otp scan ~/Desktop/qr.png
```

두 형식을 모두 읽습니다.

| QR 종류 | 내용 |
|---|---|
| `otpauth://totp/...` | 서비스에서 2FA 를 켤 때 나오는 일반 QR. 계정 1개 |
| `otpauth-migration://offline?data=...` | Google Authenticator 의 "계정 내보내기" QR. **계정 여러 개가 한 번에** |

내보내기 QR 은 한 장에 여러 계정이 들어 있어 한 번에 모두 등록됩니다.
이름은 issuer 에서 따오고, 같은 이름이 이미 있으면 덮어쓰지 않고 `-2`, `-3` 을 붙입니다.

`otp scan` 은 이름을 issuer 에서 자동으로 만듭니다. 마음에 안 들면 바꾸면 됩니다.

```sh
otp list
otp rename amazon-web-services aws
```

> [경고] QR 을 온라인 QR 리더 사이트에 올리지 마세요. QR 안에는 시크릿이 그대로 들어 있어서,
> 한 번 넘어가면 상대가 언제든 유효한 코드를 만들 수 있습니다. `otp scan` 은 Vision 프레임워크로
> 이 맥 안에서만 디코드하며 어디에도 전송하지 않습니다.

HOTP(카운터 기반) 계정은 건너뜁니다. 지원 대상이 TOTP 뿐입니다.

## 단축키로 바로 입력하기

OTP 입력란에 커서를 두고 단축키(기본 `⌘⌥O`)를 누르면 코드가 바로 타이핑됩니다.
클립보드를 거치지 않으므로 코드가 클립보드 이력에 남지 않습니다.

```sh
brew services start otp        # 로그인 시 자동으로 단축키 대기
```

등록이 **하나면** 단축키를 누르는 즉시 그 코드가 입력됩니다.
**여러 개면** 마우스 위치에 목록이 떠서 고르면 입력됩니다. 숫자키 `1`~`9` 로 바로 고를 수 있고,
화살표나 이름 첫 글자로도 선택됩니다.

```sh
otp default gitlab             # 자주 쓰는 계정을 목록 맨 위(1번)로
otp agent --account gitlab     # 목록 없이 한 계정만 쓰도록 고정
```

목록이 뜨는 동안에는 포커스가 잠깐 넘어오지만, 고르고 나면 원래 앱으로 되돌린 뒤 입력합니다.

처음 실행하면 **손쉬운 사용 권한**을 요청합니다. 시스템 설정 → 개인정보 보호 및 보안 →
손쉬운 사용 에서 `otp` 를 허용한 뒤 다시 실행하세요. 합성 키 입력을 보내려면 필요한 권한입니다.

단축키를 바꾸려면:

```sh
otp hotkey                    # 현재 설정 보기
otp hotkey "ctrl+opt+/"       # 변경 (저장됨)
brew services restart otp     # 실행 중이면 재시작해야 반영
```

수정키(cmd/opt/ctrl/shift) 를 최소 하나 포함해야 합니다.
문자·숫자 외에 `/ - = [ ] ; ' , . \\ \`` 와 `space`, `tab`, `return`, `f1`~`f12` 를 쓸 수 있습니다.
기호키 쪽이 다른 앱과 덜 겹칩니다.

다른 앱이 이미 쓰는 조합이면 agent 가 등록에 실패하며 그 사실을 알려줍니다.

```
otp: 단축키 ⌘⌥O 를 등록하지 못했습니다. 다른 앱이 이미 쓰고 있을 수 있습니다.
```

`--hotkey` 옵션은 그 실행에만 적용되고 저장되지 않습니다. `brew services` 로 띄울 때는
`otp hotkey` 로 저장한 값이 쓰입니다.

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
