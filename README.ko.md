# ccv

**Claude Code 버전 매니저** — 심볼릭 링크 하나로 여러 Claude Code 버전을 설치·전환·관리합니다.

```
ccv install 1.3.0 && ccv use 1.3.0
```

`nvm`에서 영감을 얻어, `zsh` 환경에 맞춰 만들었습니다.

## 빠른 시작

설치하고, 쉘을 리로드한 뒤 바로 사용할 수 있습니다.
`zsh`와 `git`이 필요합니다.

```sh
# 설치
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh

# 쉘 리로드
source ~/.zshrc

# 버전 설치 및 활성화
ccv install 1.3.0
ccv use 1.3.0
ccv current    # → 1.3.0
```

## 설치 방법

잘 모르겠다면 installer를 사용하세요.

### 권장 설치 (installer)

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | sh
```

`~/.ccv`에 `ccv`를 설치하고, `~/.zshrc`에 `source` 라인을 추가하며, zsh 자동완성도 함께 설정합니다.

### 특정 버전 설치

```sh
curl -fsSL https://raw.githubusercontent.com/CoodingPenguin/ccv/main/install.sh | CCV_VERSION=v0.1.0 sh
```

`CCV_VERSION`에는 임의의 git 태그나 브랜치 이름을 지정할 수 있습니다 (기본값: `main`).

### 수동 설치

```sh
git clone --depth 1 https://github.com/CoodingPenguin/ccv.git ~/.ccv
echo 'fpath=("$HOME/.ccv/completions" $fpath)' >> ~/.zshrc
echo '[[ -f "$HOME/.ccv/ccv.sh" ]] && source "$HOME/.ccv/ccv.sh"' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc
```

## 사용법

```
ccv <command> [options]

Commands:
  current                현재 활성 버전 출력
  ls                     설치된 버전 목록
  ls-remote [N]          사용 가능한 버전 목록 (기본 15개)
  review                 현재 버전 이후 변경점 검토
  install <version>      버전 설치
  use [version]          버전 전환 (기본: 최신 설치 버전)
  rm <version>           버전 제거
  upgrade                최신 버전 설치 + 전환
  self-update            ccv 자체 업데이트
  notify [on|off]        새 버전 알림 토글
  --help, -h             도움말
  --version, -v          버전 확인
```

### 버전 설치

```sh
ccv install 1.3.0          # 특정 버전 설치
ccv upgrade                # 최신 버전 설치 + 전환
ccv review                 # 업데이트 전 공식 변경점 검토
```

### 버전 목록

```sh
ccv ls                     # 설치된 버전 (현재 활성 버전 강조)
ccv ls-remote              # 레지스트리 기준 최신 15개
ccv ls-remote 50           # 최신 50개
```

### 버전 전환

```sh
ccv use 1.3.0              # 특정 버전으로 전환
ccv use                    # 최신 설치 버전으로 전환
ccv current                # 현재 활성 버전 확인
```

전환 시 `CCV_LINK`(기본 `~/.local/bin/claude`)의 심볼릭 링크가 선택된 버전을 가리키도록 갱신됩니다.

### 버전 제거

```sh
ccv rm 1.2.0
```

### 알림

```sh
ccv notify on              # 새 버전 알림 켜기
ccv notify off             # 끄기
```

활성화 시 `ccv`가 주기적으로 레지스트리를 확인하고 새 버전이 있으면 알려줍니다.

### 무엇이 달라졌는지 검토

```sh
ccv review
```

`ccv review`는 현재 활성 버전과 최신 버전을 비교하고, Claude Code 공식 changelog를 가져와 아래 정보를 요약합니다:

- 현재 버전과 최신 버전
- 이번 검토에 포함된 버전 범위
- 현재 버전 이후의 중요한 변경
- MCP, permissions, agents, shell, config, keybindings 같은 민감 영역
- 지금 올릴지 보류할지 판단하는 데 도움이 되는 참고 신호

npm 최신 버전이 changelog 문서보다 앞서 있으면, 문서화된 릴리스까지만 검토하고 최신 릴리스가 미문서 상태임을 경고합니다.

### ccv 업데이트

```sh
ccv self-update
```

git 기반 설치(`~/.ccv`)의 경우 `git pull` 후 `ccv.sh`를 다시 소스합니다.

## 자동완성

Installer는 zsh 자동완성을 자동으로 설정합니다:

```
ccv <TAB>         → current, ls, ls-remote, review, install, use, rm, upgrade, self-update, notify
ccv use <TAB>     → 설치된 버전 목록
ccv rm <TAB>      → 설치된 버전 목록
ccv install <TAB> → 원격 버전 목록
```

수동 설치의 경우 `.zshrc`에 다음이 포함되어 있어야 합니다:

```zsh
fpath=("$HOME/.ccv/completions" $fpath)
autoload -Uz compinit && compinit
```

## 설정

| 환경변수      | 기본값                             | 설명                          |
| ------------ | -------------------------------- | ----------------------------- |
| `CCV_DIR`    | `~/.local/share/claude/versions` | 버전이 설치되는 디렉토리       |
| `CCV_LINK`   | `~/.local/bin/claude`            | `claude` 심볼릭 링크 경로     |
| `CCV_CHANGELOG_URL` | 공식 GitHub raw changelog | changelog 소스 URL 재정의     |

`CCV_LINK`가 위치한 디렉토리가 `PATH`에 포함되어 있어야 합니다.

## 동작 방식

각 버전은 `CCV_DIR/<version>/` 아래에 설치됩니다.
`ccv use <version>`은 `CCV_LINK` 위치의 심볼릭 링크를 선택한 버전을 가리키도록 갱신해 `claude` 명령이 해당 버전을 실행하게 합니다.
재설치나 재빌드 없이 즉시 전환됩니다.

## 요구사항

- **zsh**
- **git**

## 제거

```sh
~/.ccv/uninstall.sh
```

`~/.ccv`와 `~/.zshrc`의 `source` 라인을 제거합니다.
`CCV_DIR` 아래의 설치된 Claude Code 버전은 삭제되지 않습니다.

## 라이선스

[MIT](LICENSE)
