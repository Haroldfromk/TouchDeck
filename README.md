# TouchDeck

아이패드/아이폰을 맥의 스트림덱처럼 쓰는 개인용 앱. iOS 앱(`TouchDeck/`), 맥 메뉴바 앱(`TouchDeckMac/`), 공용 패키지(`Packages/DeckKit/`)로 나뉜다. 설계는 `docs/superpowers/specs/2026-10-19-touchdeck-design.md`.

## 맥 앱을 /Applications에 설치하기

메뉴바 창의 "로그인 시 자동 실행"은 지금 실행 중인 앱 경로를 등록한다. Xcode에서 띄운 빌드(DerivedData)로 켜면 로그인 때 그 빌드가 뜨니, Release로 빌드해서 /Applications에 넣은 앱에서 켠다.

```bash
xcodegen generate
```

```bash
xcodebuild build -project TouchDeck.xcodeproj -scheme TouchDeckMac -configuration Release -derivedDataPath DerivedData -allowProvisioningUpdates
```

실행 중인 TouchDeck(Xcode에서 띄운 것 포함)을 먼저 끄고 복사한다. 포트 52801은 한 앱만 쓸 수 있다.

```bash
ditto DerivedData/Build/Products/Release/TouchDeck.app /Applications/TouchDeck.app
```

```bash
open /Applications/TouchDeck.app
```

그다음 메뉴바 창에서 "로그인 시 자동 실행"을 켠다. "시스템 설정 > 일반 > 로그인 항목에서 허용해 주세요"가 뜨면 거기서 TouchDeck을 허용한다.

손쉬운 사용 권한(볼륨 키, 숫자 키패드)은 앱 위치마다 따로 받는다. /Applications 앱을 처음 띄우면 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 다시 켜야 할 수 있다.

## 테스트

```bash
cd Packages/DeckKit && swift test
```

```bash
xcodebuild test -project TouchDeck.xcodeproj -scheme TouchDeckMac -derivedDataPath DerivedData -allowProvisioningUpdates
```
