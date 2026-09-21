# otp

TOTP(RFC 6238) 코드를 생성하는 macOS CLI. 시크릿은 macOS Keychain 에 저장한다.

## 커밋 신원 — 전역 git 설정을 쓰지 않는다

이 저장소는 공개 저장소다. 커밋 작성자는 반드시 아래로 고정한다.

```
kube-guy <324278276+kube-guy@users.noreply.github.com>
```

**전역 `~/.gitconfig` 가 이 저장소의 커밋에 쓰이게 두지 않는다.** 거기에는 업무용 신원
(실명 + 회사 이메일)이 들어 있고, 한 번 푸시되면 되돌릴 수 없다.

커밋을 만드는 작업 전에 매번 확인한다.

```sh
git var GIT_AUTHOR_IDENT   # kube-guy <324278276+kube-guy@users.noreply.github.com> 여야 한다
```

- 값이 다르면 커밋하지 말고 `git config user.name` / `user.email` 을 먼저 설정한다.
- **`-c user.email=...` 을 커밋마다 붙이는 방식에 의존하지 않는다.** `git merge`,
  `git rebase`, `git cherry-pick`, `git revert` 는 커밋을 만들면서도 이 지정이 빠지기 쉽다.
- 푸시 전에 `git log --format='%an <%ae>'` 로 **전체** 커밋의 작성자를 확인한다.
- `.git/config` 와 `~/.gitconfig` 의 `[includeIf "gitdir:~/otp-cli/"]` 양쪽에 같은 신원이 걸려 있다.
- 공개될 파일에 실명·회사 이메일·개인 이메일을 적지 않는다.

## 보안상 지켜야 할 것

- **실제 TOTP 시크릿을 소스·테스트·문서·커밋 메시지에 넣지 않는다.** 저장소에 있는
  Base32 문자열은 RFC 6238 Appendix B 의 공개 테스트 벡터뿐이다.
- 시크릿을 `print` 하거나 로그에 남기지 않는다. 등록 시 입력은 `getpass` 로 받아 화면에 표시하지 않는다.
- Keychain 읽기·쓰기는 `/usr/bin/security` 를 거친다. 이유는 README 참고.
- 코드 출력은 stdout, 부가 정보는 stderr 로 분리한다. 파이프로 쓰는 경우가 있다.

## 빌드·검증

```sh
swift build -c release
./.build/release/otp selftest   # RFC 6238 벡터 검증. 변경 후 반드시 통과시킬 것
```

XCTest 는 전체 Xcode 에만 포함되므로 쓰지 않는다. 검증은 `SelfTest.swift` 에 두고
`otp selftest` 로 실행한다. `brew test` 도 이 명령을 쓴다.

이 파일이 정본이고 `CLAUDE.md` 는 심볼릭 링크다.
