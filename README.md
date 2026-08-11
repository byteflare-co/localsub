<p align="center">
  <img src="Config/LocalSub-AppIcon.png" width="160" alt="LocalSub アプリアイコン">
</p>

<h1 align="center">LocalSub</h1>

<p align="center">
  Apple Silicon向け、プライバシー重視の動画用日本語字幕アプリ。
</p>

<p align="center">
  <img alt="macOS 26以降" src="https://img.shields.io/badge/macOS-26%2B-111827?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-native-2563EB">
  <img alt="ローカルファースト" src="https://img.shields.io/badge/processing-local--first-06B6D4">
  <a href="LICENSE"><img alt="Apache License 2.0" src="https://img.shields.io/badge/license-Apache--2.0-0B7285"></a>
</p>

<p align="center">
  <a href="docs/README.en.md">English</a> ·
  <a href="#ビルドとテスト">ビルド</a> ·
  <a href="docs/architecture/software-design.md">アーキテクチャ</a> ·
  <a href="docs/security/threat-model.md">脅威モデル</a> ·
  <a href="CONTRIBUTING.md">コントリビューション</a> ·
  <a href="GOVERNANCE.md">ガバナンス</a> ·
  <a href="SECURITY.md">セキュリティ</a> ·
  <a href="LICENSE">ライセンス</a>
</p>

LocalSubは、動画内の日本語または英語の音声を編集可能な日本語字幕へ変換し、
字幕付きの新しい動画として書き出すmacOSデスクトップアプリです。

プライバシーを重視したローカルファースト設計を採用しています。最初の対応範囲は、
macOS 26以降を搭載したApple Silicon Macと、AVFoundationでデコード可能なSDRの
MP4／MOVファイルです。

> [!IMPORTANT]
> LocalSubは現在開発中です。公式に署名されたバイナリリリースはまだ公開していません。
> ローカルビルドは開発とドッグフーディングを目的としています。

## リポジトリ構成

- `Sources/LocalSubCore`: 決定論的なドメインロジックとプロバイダー契約
- `Sources/LocalSubApple`: Apple Speech、Translation、AVFoundationのアダプター
- `Sources/LocalSubCloud`: 任意で利用できる、制限付きGPT-5.6 Lunaテキスト翻訳アダプター
- `Sources/LocalSubCLI`: 開発・ドッグフーディング用CLI
- `Sources/LocalSubApp`: SwiftUIデスクトップアプリ
- `Tests`: TDDによるユニットテストと統合テスト
- `docs/architecture`: 設計およびアーキテクチャ決定記録
- `docs/security`: リポジトリの脅威モデル
- `docs/qa`: ドッグフーディング項目と手動検証用アセット

正式な設計は[software-design.md](docs/architecture/software-design.md)を参照してください。

## ビルドとテスト

LocalSubの開発には、Apple Silicon、macOS 26、Xcode 26以降が必要です。

```bash
swift test --scratch-path /tmp/localsub-tests
./scripts/build-app.sh
open .build/app/LocalSub.app
```

このビルドスクリプトは、アドホック署名とサンドボックスを適用したローカル検証用アプリを生成します。
Desktopアプリの配布可能なビルドには、Developer ID署名、Hardened Runtime、公証、Staplingが追加で必要です。
アドホック署名のビルドは、意図どおりGatekeeperの評価に合格しません。

リリース担当者は`scripts/build-release.sh`を使用します。このスクリプトは署名IDまたは
`notarytool`のキーチェーンプロファイルがなければfail-closedし、最後に`stapler validate`と
`spctl --assess`を実行します。

Desktopアプリに関するApple Developer Program、Developer ID、公証、Mac App Storeの要件は
[配布ガイド](docs/distribution.md)を参照してください。

## 開発者向けCLI

### インストール

```bash
brew install byteflare-co/tap/localsub
localsub doctor
```

Homebrewを使わない場合：

```bash
curl -fsSLO https://github.com/byteflare-co/localsub/releases/download/v0.1.0-alpha.2/install.sh
less install.sh
sh install.sh
~/.local/bin/localsub doctor
```

プレリリースはGitHubの`releases/latest`には含まれないため、URLをバージョン固定しています。
CLIは固定されたソースアーカイブを検証し、ユーザーのMac上でビルドします。Apple Developer Programは
不要ですが、Xcode 26以降が必要です。対応環境はApple SiliconとmacOS 26以降です。
初回モデル準備、インストーラーの検証内容、
リリース工程は[CLIの配布とリリース](docs/cli-distribution.md)を参照してください。

### 使い方

```bash
swift run --scratch-path /tmp/localsub-cli localsub input.mp4 \
  --output captioned.mp4 --language japanese
```

初回利用前に`localsub doctor`を実行してください。Speechモデルがなければ、表示内容を確認してから
`localsub setup --language japanese --accept-model-download`で準備できます。

更新確認は既定で無効です。接続先と送信内容を確認し、利用者が
`localsub update-check enable --acknowledge-metadata`を実行した場合だけ、通常コマンドの起動時に最大24時間に1回
GitHub Releasesを確認します。動画・音声・字幕・パス・ファイル名は送信せず、自動更新もしません。
GitHubとネットワーク事業者からは、通常の接続情報（IP、時刻、接続先）とLocalSubバージョンを観測できます。
`--help`と`--version`は常に通信しません。`localsub update-check disable`で再び無効化でき、
`LOCALSUB_NO_UPDATE_CHECK=1`で有効な設定を一時停止できます。

英語音声には`--language english`を指定します。標準のApple Translationは、すでにインストール済みの
モデルだけを使用します。`--translation luna`を指定するとGPT-5.6 Lunaを明示的に選択でき、
そのプロセスへ`OPENAI_API_KEY`を注入する必要があります。`--glossary terms.txt`には最大32 KiBの
`source=日本語`形式の用語を指定できます。

LunaをCLIで使用する場合は、コマンドが表示するデータ送信の説明を読んだうえで、
`--acknowledge-luna-data-transfer`も指定する必要があります。APIキーは絶対にコミットしないでください。
進捗は標準エラー出力へ、1行につき1つのJSONオブジェクトとして出力されます。

デスクトップアプリはOpenAI APIキーを、同期されないローカルのmacOS Keychainへ保存できます。
Lunaモードは生成のたびに確認を求め、端末内で生成した英語の文字起こし単位と用語集だけを送信します。
動画、音声、パス、ファイル名は送信しません。リクエストでは`store: false`を指定し、Responseオブジェクトの
標準保存を無効化します。APIの組織・プロジェクトに該当するデータ制御がない場合、OpenAIは別途、
不正利用監視用データを最大30日、暗号化されたプロンプトキャッシュを最大24時間保持すると説明しています。
完全にローカルで翻訳したい場合は、Apple Translationを利用できます。

デスクトップアプリでは、2行字幕の編集、字幕を焼き込んだMP4の書き出し、UTF-8 SRTの個別保存ができます。
MP4の書き出し時は、サンドボックス内で安全にステージングし、固定された出力ファイル名をアトミックに
公開するため、保存先フォルダを選択します。既存ファイルを暗黙に上書きすることはありません。

## コントリビューションとサポート

コントリビューションを歓迎します。Pull Requestを作成する前に[CONTRIBUTING.md](CONTRIBUTING.md)を読み、
バグや機能提案には所定のIssueテンプレートを使用し、[行動規範](CODE_OF_CONDUCT.md)を守ってください。
意思決定の方法は[GOVERNANCE.md](GOVERNANCE.md)、サポート範囲は[SUPPORT.md](SUPPORT.md)に記載しています。

脆弱性は[SECURITY.md](SECURITY.md)に従って非公開で報告してください。公開Issueには、非公開の動画、
文字起こし、認証情報、署名関連ファイルを添付しないでください。

## ライセンス

LocalSubは[Apache License 2.0](LICENSE)で公開しています。Copyright 2026 株式会社Byteflare。
ライセンス条件に従い、商用利用、変更、再配布が可能です。合理的な帰属表示を除き、LocalSubまたは
株式会社Byteflareの名称・ブランドを使用する権利は付与されません。
