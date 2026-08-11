# CLIの配布とリリース

LocalSub CLIは、Apple SiliconとmacOS 26以降を対象に、署名・公証済みの単一バイナリとして
GitHub Releasesから提供します。GitHub Releaseが配布物の正本で、curlインストーラーと
Homebrew Caskは同一のバージョン固定ZIPを参照します。

## 利用者向けインストール

推奨経路はHomebrewです。

```bash
brew install --cask byteflare-co/tap/localsub
localsub doctor
```

Homebrewを使わない場合は、GitHubのバージョン固定Immutable Releaseに含まれるインストーラーを利用できます。

```bash
curl -fsSL https://github.com/byteflare-co/localsub/releases/download/v0.1.0-alpha.1/install.sh | sh
~/.local/bin/localsub doctor
```

`curl | sh`は取得したシェルコードを直ちに実行します。内容を先に確認する場合は次のようにします。

```bash
curl -fsSLO https://github.com/byteflare-co/localsub/releases/download/v0.1.0-alpha.1/install.sh
less install.sh
sh install.sh
```

GitHubの`releases/latest`はプレリリースを返さないため、プレリリース期間中は必ずバージョンを固定します。
安定版公開後は、READMEの推奨URLをGitHubのlatestリリースURLへ切り替えます。

インストーラーは`sudo`を使用せず、標準では`~/.local/bin/localsub`へ配置します。対象OS・CPU、
SHA-256、ZIP内容、Developer ID署名、Apple Developer Team Identifier、コード署名Identifier、
公証状態を検証し、すべて成功した場合だけ同一ボリューム上で公開します。

## 初回セットアップ

```bash
localsub doctor --language japanese
localsub setup --language japanese --accept-model-download
```

`setup`は指定言語のApple Speechモデルだけを、明示的な同意後に導入します。英日Apple Translationの
初回モデル利用にはUI上の同意が必要なため、LocalSubデスクトップアプリで準備してください。
CLIだけで完結させる場合は、データ送信条件を確認してLuna翻訳を明示的に選択できます。

## リリース担当者向け手順

前提条件：

- `株式会社Byteflare`のApple Developer Program組織アカウント
- Keychainに導入済みの`Developer ID Application`証明書
- `notarytool`のKeychain profile
- 10文字のApple Developer Team ID
- `gh`で`byteflare-co/localsub`へ管理者認証済み
- GitHub Immutable Releasesが有効

認証情報はリポジトリへ保存しません。Apple ID、app-specific password、API秘密鍵などをローカルで
扱う場合は、ユーザーグローバルの`op-cached`から子プロセスへ注入します。

1. `LocalSubVersion.current`とリリースノートを更新し、全テストを通す。
2. リリースコミットを`main`へmergeする。
3. `v<version>`の軽量タグを作り、originへpushする。
4. 署名・公証済み資産を生成する。

```bash
export LOCALSUB_SIGNING_IDENTITY='Developer ID Application: ...'
export LOCALSUB_NOTARY_PROFILE='localsub-notary'
export LOCALSUB_EXPECTED_TEAM_ID='XXXXXXXXXX'

./scripts/check-cli-release-credentials.sh

release_dir=$(mktemp -d /tmp/localsub-release-output.XXXXXX)
./scripts/build-cli-release.sh "$release_dir"
```

5. ZIP、`install.sh`、`SHA256SUMS`、Homebrew Caskを別々に確認する。
6. Draft Releaseを作成し、全assetのアップロード後に公開する。

```bash
./scripts/publish-cli-release.sh "$release_dir" \
  "$PWD/docs/releases/v0.1.0-alpha.1.md"
```

公開スクリプトは、クリーンなタグ付きHEAD、remote tag一致、チェックサム、Immutable Releases有効化を
再確認します。既存Releaseの置換は行いません。

7. 生成された`localsub.rb`を`byteflare-co/homebrew-tap`の`Casks/localsub.rb`として反映する。
8. curlとHomebrewの両方を、既存インストールのない別ユーザー領域で確認する。

## 公開後の確認

- GitHub ReleaseがImmutableか
- tag・target commit・`main` HEADが一致するか
- `gh release verify`と`gh release verify-asset`が成功するか
- curlインストール後の署名・Team ID・公証状態が一致するか
- Homebrewのinstall、upgrade、uninstallが成功するか
- `localsub doctor`と、非機密の短い動画による字幕付きMP4生成が成功するか

署名・公証・実動画生成のいずれかが未確認なら、一般提供完了として扱いません。
