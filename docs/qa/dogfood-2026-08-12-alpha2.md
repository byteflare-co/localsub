# LocalSub CLI v0.1.0-alpha.2 公開dogfood

実行日: 2026-08-12 JST

対象はGitHub Releaseと`byteflare-co/tap`から一般公開されたHomebrew版。テスト用動画・音声・画像は
OS一時ディレクトリだけで生成し、証跡照合後に削除する。

## 判定サマリ

FAIL、BLOCKED、未検証なし。公開経路、更新、更新確認、CLI-N-01相当の字幕動画生成を検証した。
独立ジャッジもCLI-N-01相当をPASSと判定した。

## ケース別

| TestID / scope | 判定 | 根拠 | 未確認 |
|---|---|---|---|
| 公開Release | PASS | tag commit `76dbd0ab9daad29e3e347e4f180bc6bd3bf33108`、5 assetのGitHub digestとローカルSHA-256一致、immutable prerelease | なし |
| Homebrew upgrade | PASS | 公開tapから`0.1.0-alpha.1 -> 0.1.0-alpha.2`をsource build、`brew test`成功 | なし |
| CLI-N-05 | PASS | 初期`disabled`、acknowledgement付きenable、実GitHub確認cache、disable後`disabled`。91 unit/integration testsで無通信policy、256 KiB streaming cap、並行process lock、strict URL/SemVer、NDJSONを確認 | 新release通知本文はfixtureで確認 |
| CLI-N-01 | PASS | 公開`/opt/homebrew/bin/localsub`、doctor `READY`、全6 stage、H.264 + AAC、入力5.880998秒・出力5.900000秒、差0.019002秒 | なし |
| 字幕可視性 | PASS | 4時点contact sheetと各秒signalstatsで背景・日本語glyphを確認。MP4 SHA-256 `15b8fadf8ce8bc9353f9e1e1134d7fb4e0bb1231ea8e1ce16a6f1b642de42e90` | なし |

## 公開工程で検出・修正した問題

GitHub Draft作成直後にrelease一覧へ反映されないeventual consistencyを、回数制限付きread-backへ変更した。
その後、実公開でGitHub CLIが`--slurp`と`--jq`の併用を拒否することを検出した。Draftのまま停止し、
資産を公開しなかった。`--paginate --jq`へ修正し、fake `gh`回帰テスト、実Draft read-back、独立レビュー、
全CIを通した。既存DraftのID、tag commit、asset名、件数、各digestを再照合してから公開した。

## 差し戻し必須事項

なし。

## 改善提案

なし。

## 記憶へ残すべき失敗の型

- GitHub CLIフラグ互換性 / release tooling変更時 / fake CLIが実CLIの禁止組合せも再現することと、Draft公開前に実read-back smokeを行う / `--slurp --jq`がfakeでは通り実CLIで停止 / 高
