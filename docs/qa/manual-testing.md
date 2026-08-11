# manual-testing 設定（LocalSub）

manual-testing スキルが LocalSub を検証するためのプロジェクト固有設定。
状態、チェック結果、RUN_ID はこのファイルに書かない。

## 環境

| 項目 | 内容 |
|---|---|
| 通常起動 | `./scripts/build-app.sh && open .build/app/LocalSub.app` |
| 無人/AI検証向け起動 | `swift run --scratch-path /tmp/localsub-cli localsub INPUT --output OUTPUT --language japanese` |
| 主要エンドポイント | アプリ固有サーバーなし。Luna選択時だけ `POST https://api.openai.com/v1/responses` |
| 健全性確認 | `swift test --scratch-path /tmp/localsub-tests`、`codesign --verify --deep --strict .build/app/LocalSub.app` |
| 対象環境 | Apple Silicon、macOS 26以降、Xcode 26以降 |
| 環境の癖 | Documents 配下では SwiftPM の `build.db` I/O error が出ることがあるため、scratch path は `/tmp` を使う。Apple Speech/Translation のモデル導入状態は端末依存 |
| ローカル署名 | `build-app.sh` は App Sandbox + Hardened Runtime の ad-hoc build。Gatekeeper 配布判定は対象外 |
| 配布候補 | `scripts/build-release.sh`。Developer ID identity と notarytool profile が必要で、notarize/staple/`spctl` 成功まで fail-closed |

## ブラウザ

| 項目 | 内容 |
|---|---|
| 使用プロファイル | 該当なし。Desktop UI は computer-use で通常の macOS セッションを操作する |
| 代替プロファイル | なし |
| 注意 | Chrome/ブラウザE2Eで native UI の成功を代替しない。ファイル選択・Save panel・security-scoped bookmark は実アプリで確認する |

## サンドボックス（自動送信してよい宛先の明示的リスト）

テスト素材と出力は、リポジトリ配下の
`tmp/e2e-runs/<RUN_ID>/` または OS の一時ディレクトリに限定する。
Apple管理モデルの初回導入ダイアログが出た場合、ダウンロード開始は人間承認後のみ行う。
Luna通信は、テスト用API projectのkeyを `op-cached` から対象processへ注入し、英語・Lunaを
明示選択して送信確認に同意したrunだけ許可する。音声、動画、path、filenameは送信禁止。

| 種別 | 識別子 | 用途 |
|---|---|---|
| ローカルディレクトリ | `tmp/e2e-runs/<RUN_ID>/` | 合成入力、出力、スクリーンショット、ログ |
| HTTPS | `https://api.openai.com/v1/responses` | 同意済みLuna runの英文翻訳だけ |

## 手順書

| 項目 | 場所 |
|---|---|
| 機能一覧 | `docs/qa/feature-inventory.md` |
| Desktop scope | `docs/qa/runbook-desktop.md` — SwiftUI、ファイル権限、日英生成、編集、MP4/SRT、取消・復旧 |
| CLI scope | `docs/qa/runbook-cli.md` — 開発CLIの再現実行、進捗、exit code、media policy、出力検査 |
| 実行コピー・成果物 | `tmp/e2e-runs/<RUN_ID>/`（コミットしない） |

## 検証用の定番コマンド

```bash
swift test --scratch-path /tmp/localsub-tests
./scripts/build-app.sh
codesign -dvv .build/app/LocalSub.app
codesign -d --entitlements - .build/app/LocalSub.app
ffprobe -v error -show_streams -show_format OUTPUT.mp4
ffmpeg -hide_banner -loglevel error -i OUTPUT.mp4 -vf 'fps=1,scale=480:-1,tile=4x2' -frames:v 1 CONTACT.png
shasum -a 256 INPUT.mp4 OUTPUT.mp4
```

## 学習ファイル

`docs/qa/manual-testing-learnings.md`
