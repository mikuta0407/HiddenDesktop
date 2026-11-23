# HiddenDesktop

メニューバーからワンクリックで、デスクトップのアイコンとウィジェットを隠したり表示したりする macOS アプリ。

## インストール

```sh
brew install --cask mikuta0407/apps/hiddendesktop
```

## 使い方

| 操作 | 内容 |
|---|---|
| メニューバーの 👁 を左クリック / `⌃⌥⌘H` | 隠す ⇄ 表示 |
| 右クリック (または `⌥` + クリック) | メニュー (ウィジェットも隠す / ログイン時に起動 / 終了) |

## 仕組み

- **アイコン**: `com.apple.finder` の `CreateDesktop` を `false` にして Finder を再起動
- **ウィジェット**: `com.apple.WindowManager` の `StandardHideWidgets` / `StageManagerHideWidgets` を `true` にする
  (システム設定の「ウィジェットを表示: デスクトップ」と同じ設定。即時反映)。
  隠す前の値を覚えておき、表示に戻すときに復元します。

壁紙の上に画像を重ねる方式ではないので、ダイナミック壁紙や空撮 (動画) 壁紙でもそのまま使えます。

## 注意

- アイコンの切り替え時に Finder が再起動するため、一瞬のラグがあります。
- アプリを終了すると (メニューの「終了」、`kill` などでも) デスクトップは表示状態に戻ります。
  強制終了 (`kill -9`) やクラッシュの場合のみ隠れたまま残るので、その時はもう一度起動して切り替えてください。
- 公証していない (ad-hoc 署名) アプリです。

## ビルド

```sh
./build.sh          # build/HiddenDesktop.app
./build.sh --zip    # 配布用 zip も作成
```

要件: macOS 13 以降、Xcode Command Line Tools
