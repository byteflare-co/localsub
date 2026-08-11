# LocalSub 機能・連続ユースケース一覧

基準リビジョン: `codex/localsub` current worktree（2026-08-11 dogfood）

設計上の予定ではなく、現行コードとテストで確認できるものを列挙する。

## 機能一覧

| ID | 機能 | 状態 | 実装根拠 | 主な手動ケース |
|---|---|---|---|---|
| F-01 | sandboxed SwiftUI Desktop 起動・空状態 | 実装済み | `Sources/LocalSubApp/LocalSubApp.swift:9-23,295-337` | DSK-N-01 |
| F-02 | MP4/MOV選択とsecurity-scoped bookmark復元 | 実装済み（端末権限依存。M4Vも実装上は受理） | `Sources/LocalSubApp/LocalSubApp.swift:51-77,96-134,288-291` | DSK-N-02, DSK-N-06 |
| F-03 | MP4/MOV/M4V、H.264/HEVC、AAC/PCM、SDR、4K、2時間、60fps等の検査 | 実装済み | `Sources/LocalSubApple/MediaInspector.swift:9-70`; `Sources/LocalSubCore/MediaPolicy.swift:45-76` | DSK-E-01, DSK-B-01, CLI-E-01 |
| F-04 | 動画からM4A音声抽出 | 非UI・裏側 | `Sources/LocalSubApple/AudioExtractor.swift:8-27` | DSK-N-02, CLI-N-01 |
| F-05 | 日本語の時刻付きオンデバイス音声認識 | 実装済み（Apple model依存） | `Sources/LocalSubApple/AppleSpeechTranscriber.swift:16-50` | DSK-N-02, CLI-N-01 |
| F-06 | 英語音声認識→Apple Translationまたは明示同意Lunaで日本語化 | 実装済み（各model/権限依存） | `Sources/LocalSubApp/LocalSubApp.swift`; `Sources/LocalSubApple/AppleTranslationProvider.swift`; `Sources/LocalSubCloud/LunaTranslationProvider.swift` | DSK-N-03, DSK-N-07, CLI-N-02, CLI-N-04 |
| F-07 | 翻訳応答のID相関、欠損・重複拒否 | 非UI・裏側 | `Sources/LocalSubCore/Translation.swift:27-59`; `Tests/LocalSubCoreTests/TranslationCorrelationTests.swift` | API/Fake契約テストで代替 |
| F-08 | 日本語字幕の2行分割・読速警告 | 実装済み | `Sources/LocalSubCore/CueBuilder.swift:27-61`; `Sources/LocalSubApp/LocalSubApp.swift:365-377` | DSK-N-04, DSK-B-02 |
| F-09 | 動画再生位置に同期した字幕プレビュー | 実装済み | `Sources/LocalSubApp/LocalSubApp.swift:88-94,279-285,339-351` | DSK-N-02, DSK-B-03 |
| F-10 | 字幕本文編集 | 実装済み | `Sources/LocalSubApp/LocalSubApp.swift:262-268,365-372` | DSK-N-04 |
| F-11 | Core Graphics共通rasterizerによるpreview/export | 実装済み | `Sources/LocalSubApple/SubtitleVideoExporter.swift:100-175`; `Sources/LocalSubApp/LocalSubApp.swift:462-482` | DSK-N-02, DSK-B-03 |
| F-12 | 字幕焼き込みMP4出力・staging検証 | 実装済み | `Sources/LocalSubApple/SubtitleVideoExporter.swift:13-98` | DSK-N-02, DSK-E-03 |
| F-13 | 既存ファイル・symlinkの排他的な非上書き公開 | 非UI・裏側 | `Sources/LocalSubApple/SubtitleVideoExporter.swift:178-215`; `Sources/LocalSubApple/NonReplacingFileWriter.swift` | DSK-E-04, CLI-E-03 |
| F-14 | UTF-8 SRT保存 | 実装済み | `Sources/LocalSubApp/LocalSubApp.swift:270-276,399-400`; `Sources/LocalSubCore/SRTSerializer.swift` | DSK-N-05 |
| F-15 | 生成・翻訳・exportの取消と世代隔離 | 実装済み | `Sources/LocalSubApp/LocalSubApp.swift:96-134,136-218,221-259` | DSK-E-03 |
| F-16 | 開発CLIとJSON line進捗 | 実装済み | `Sources/LocalSubCLI/main.swift:41-79` | CLI-N-01, CLI-E-02 |
| F-17 | App Sandbox + Hardened Runtime local bundle | 実装済み | `Config/LocalSubApp.entitlements`; `scripts/build-app.sh` | DSK-N-01 |
| F-18 | Developer ID/notarized配布ビルド | 実装済み（資格情報依存、未実行） | `scripts/build-release.sh` | DSK-E-06 |
| F-19 | AppKit動画previewと所有playerに紐づくobserver解除 | 実装済み・30KB fixtureで実機確認 | `Sources/LocalSubApple/AppKitPlayerSurface.swift`; `Sources/LocalSubApp/LocalSubApp.swift` | DSK-N-02, DSK-N-06 |
| F-20 | Speech model導入状態の正規化とDesktopでの明示準備 | 実装済み（英語modelの実導入は未実施） | `Sources/LocalSubApple/AppleSpeechTranscriber.swift`; `Sources/LocalSubApp/LocalSubApp.swift` | DSK-N-03, CLI-E-02 |
| F-21 | folder security-scopeを保持したMP4 staging/排他publish | 実装済み・sandbox実機確認 | `Sources/LocalSubApp/LocalSubApp.swift`; `Sources/LocalSubApple/SecurityScopedResourceAccess.swift` | DSK-N-02, DSK-E-04 |
| F-22 | Luna keyの非同期Keychain保存・削除と既存値非表示 | 実装済み | `Sources/LocalSubApple/OpenAIAPIKeyStore.swift`; `Sources/LocalSubApp/LocalSubApp.swift` | DSK-N-07, DSK-E-07 |
| F-23 | 用語集によるSpeech hintと翻訳語固定 | 実装済み（最大100件/32KiB） | `Sources/LocalSubCore/Glossary.swift`; `Sources/LocalSubApple/AppleSpeechTranscriber.swift` | DSK-N-07, CLI-N-04 |
| G-01 | プロジェクト保存、字幕編集状態の再開 | 既知ギャップ | UI導線・project storeなし | UI対象外・ギャップ |
| G-02 | cue開始/終了時刻・位置・文字サイズ・背景の編集 | 既知ギャップ | UIは本文編集のみ | UI対象外・ギャップ |
| G-03 | VoiceOver向け字幕行/編集リストの詳細ラベル | 既知ギャップ | preview labelのみ | DSK-B-04で現状評価 |
| G-04 | 無音／認識0件の明確なエラー表示 | 既知ギャップ | 0 cuesでreviewへ進み、exportが無効になる | DSK-E-02 |
| G-05 | CLIでSpeech/Translation model未導入時のDesktop準備案内 | 解消 | CLIはdownloadせずDesktop準備を明示する | CLI-E-02 |
| G-06 | M4V対応のUI・文書表示 | 既知ギャップ | inspectorは受理するが、UIの対応形式表示はMP4/MOVのみ | DSK-E-01 |

## 連続ユースケース

`CLI-E2E（ローカルprocess）`はfakeではなく、実際のCLI process、Apple model、生成mediaを使う非UIのend-to-end確認を指す。

| UC | ジャーニー | 優先度 | 実行区分 | 必要アカウント | 必要seed | cleanup | 自動化可否 | 代替API検証 |
|---|---|---:|---|---|---|---|---|---|
| UC-01 | 起動→日本語動画選択→認識→編集→preview→MP4/SRT保存→再生確認 | P0 | UI-E2E | なし | 合成日本語MP4 | 出力とbookmark削除 | 一部可 | CLI + AVFoundation integration |
| UC-02 | 起動→英語動画→初回model準備→日本語翻訳→編集→MP4保存 | P0 | UI-E2E | Apple model利用可能なmacOS user | 合成英語MP4 | 出力削除。model削除は行わない | 部分的 | 導入済みmodelならCLI |
| UC-03 | 生成/export中に取消→終了待ち→別動画で再生成 | P0 | UI-E2E | なし | 長めの合成MP4を2本 | partial output確認後削除 | fakeは可 | JobLease unit、export integration |
| UC-04 | 非対応・破損・無音・制限超過入力を選択→安全な拒否→別動画で復旧 | P1 | UI-E2E | なし | 異常fixture群 | fixtureのみ | 多くは可 | MediaInspector integration/CLI |
| UC-05 | 既存出力・symlink競合→上書きせず失敗→別名で成功 | P0 | API/Fake契約テスト＋UIスモーク | なし | 既存ファイル | 作成物削除 | 可 | NonReplacing writer integration |
| UC-06 | アプリ終了→再起動→bookmarkから動画を再検査・再表示 | P1 | UI-E2E | なし | 日本語MP4 | UserDefaults bookmark削除 | 困難 | 代替なし |
| UC-07 | CLIで日本語/英語処理、構造化進捗、exit code、成果物を検査 | P1 | CLI-E2E（ローカルprocess） | なし | 日英MP4 | 出力削除 | 可 | なし |
| UC-08 | local bundleのsandbox/runtime確認→配布候補gate確認 | P0 | API/Fake契約テスト | releaseのみDeveloper ID権限 | build artifact | archive削除 | 可 | codesign/spctl/notary log |
| UC-09 | 英語→Luna選択→key確認→送信同意→用語集付き翻訳→review | P0 | UI-E2E + API契約 | OpenAI test project | 10秒英語動画・用語集 | 出力削除、keyは明示時だけ削除 | 一部可 | URLProtocol契約テスト |

## 実行前提・ブロッカー

| 前提 | 影響 | 判断・改善方針 |
|---|---|---|
| macOS 26 / Apple Siliconでない | 全Desktop/ASR | BLOCKED。対象Macで実行する |
| ja-JP/en-US Speech model未導入 | 日英生成 | UIでAppleの準備挙動を観測。外部downloadは人間承認なしに開始しない |
| en→ja Translation model未導入 | 英語ケース | `translationTask`の許可UIを確認。拒否ケースと承認ケースを分ける |
| GPT-5.6 LunaがAPI projectで未許可 | Luna成功ケース | BLOCKED。`model_not_found`を成功扱いせず、project access反映後に再実行 |
| Developer ID/notary資格情報なし | 配布候補gate | local dogfoodと分離し、DSK-E-06をBLOCKED記録。ad-hocをPASSに代用しない |
| 2時間境界の実動画なし | duration境界 | 小型fixtureのmetadata/API testで代替し、UI実処理はNOT-RUN理由を残す |
| 実在会話動画 | privacy | 使用しない。`say`等の合成音声だけを使う |
