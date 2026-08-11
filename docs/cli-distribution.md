# CLIの配布とリリース

LocalSub CLIはApple SiliconとmacOS 26以降を対象に、バージョン固定したソースから利用者のMac上で
ビルドします。実行バイナリ、Homebrew bottle、Caskは配布しません。このためCLIの利用にApple
Developer Program、Developer ID署名、Apple公証は不要です。Desktopアプリの配布要件とは別です。

## 利用者向けインストール

推奨経路はHomebrew Formulaです。Xcode 26以降が必要です。

```bash
brew install byteflare-co/tap/localsub
localsub doctor
```

Homebrewを使わない場合は、バージョン固定Immutable Releaseのインストーラーを確認して実行します。

```bash
curl -fsSLO https://github.com/byteflare-co/localsub/releases/download/v0.1.0-alpha.1/install.sh
less install.sh
sh install.sh
~/.local/bin/localsub doctor
```

一行の`curl | sh`も技術的には可能ですが、取得したコードを確認できる上記手順を推奨します。
インストーラーには対象ソースのSHA-256が直接埋め込まれています。同じ配布元から得たチェックサムを
信頼アンカーにはしません。アーカイブのハッシュ、パス、件数、展開サイズ、シンボリックリンク、
ビルド結果のバージョンを検査し、成功後だけ`~/.local/bin/localsub`へatomicに配置します。`sudo`は使いません。

## 初回セットアップ

```bash
localsub doctor --language japanese
localsub setup --language japanese --accept-model-download
```

`setup`は指定言語のApple Speechモデルだけを、明示同意後に導入します。英日Apple Translationの
初回モデル利用にはUI上の同意が必要です。CLIだけで完結させる場合は、データ送信条件を確認して
Luna翻訳を明示的に選択できます。

## リリース担当者向け手順

前提は、Apple Silicon/macOS 26、Xcode 26、`gh`のリポジトリ管理権限、GitHub Immutable Releasesです。
Appleの証明書や公証資格情報は使いません。

1. バージョンとリリースノートを更新し、全テストを通す。
2. リリースコミットを`main`へmergeする。
3. `v<version>`タグを作り、originへpushする。
4. クリーンなタグ付きHEADから配布物を生成する。

```bash
release_dir=$(mktemp -d /tmp/localsub-release-output.XXXXXX)
./scripts/build-cli-release.sh "$release_dir"
```

生成物はcustom source archive、埋め込みハッシュ付き`install.sh`、Formula、`SHA256SUMS`、
tag・commit・検証toolchainを記録した`SOURCE-METADATA.json`です。スクリプトはarchiveを別ディレクトリへ
展開してネットワーク不要の`swift build -c release --product localsub`とバージョン一致まで検証します。
FormulaではHomebrewの外側sandbox内でSwiftPMの入れ子sandboxがmacOS 26に拒否されるため、
`--disable-sandbox`はSwiftPM側だけに指定します。Homebrewのビルドsandboxは維持されます。

5. 内容を確認し、Draft Releaseを作成して全asset添付後に公開する。

```bash
./scripts/publish-cli-release.sh "$release_dir" \
  "$PWD/docs/releases/v0.1.0-alpha.1.md"
```

6. 検証済みFormulaをcleanな`byteflare-co/homebrew-tap` checkoutへbyte-for-byteでstageし、
   Formula差分だけのPRを作る。手作業のコピーや編集はしない。

```bash
./scripts/stage-homebrew-formula.sh "$release_dir" /absolute/path/to/homebrew-tap \
  0.1.0-alpha.1 "$(git rev-parse HEAD)"
```

tap側のPR CIでも`brew style`、`brew audit`、source build、`brew test`を必須にする。
7. 新しいprefixでFormulaのinstall、test、upgrade、uninstallを確認する。
8. curl経路でインストールしたCLIを、非機密の合成動画で確認する。

```bash
evidence_dir=$(mktemp -d /tmp/localsub-release-dogfood-parent.XXXXXX)/evidence
./scripts/dogfood-cli-release.sh "$(command -v localsub)" "$evidence_dir"
```

## 公開後の確認

- ReleaseがImmutableで、tag・target commit・`main` HEADが一致する
- `gh release verify`とcustom source assetの検証が成功する
- Formulaとインストーラーに埋め込まれたSHA-256がsource archiveと一致する
- Releaseに実行バイナリ、Cask、bottleが含まれない
- Homebrewのinstall、test、upgrade、uninstallが成功する
- `localsub doctor`と短い非機密動画による字幕付きMP4生成が成功する

Gatekeeperを回避するための`xattr`削除、`spctl --master-disable`、ad-hoc再署名は案内しません。
