# LocalSub CLI 手動・機能動作確認手順書

検証できないものを PASS にしない。前提未充足はスキップとして理由を記録する。
CLI成功をDesktopのfile permission、Save panel、bookmark確認の代替にしない。

## fixture準備と共通cleanup

`runbook-desktop.md`のfixture準備を実行し、同じ `RUN_DIR` を使う。各コマンドのstdout、stderr、exit code、成果物は `RUN_DIR/evidence` と `RUN_DIR/output` に保存する。成果物を既存ファイルへ向けず、証拠保持後は `RUN_DIR` 全体をFinderのゴミ箱へ移す。

## 正常系

#### CLI-N-01 日本語動画を一つのコマンドで字幕付きMP4へ変換できる
- ねらい: GUIと同じApple/Core処理を再現可能な形でドッグフードする。
- 前提: ja-JP Speech model、合成日本語H.264/AAC MP4、新規出力名。
- 手順: 1. `swift run ... localsub INPUT --output OUTPUT --language japanese`。2. stderrとexit codeを保存。3. contact sheetとSHA-256を保存する。4. `ffprobe -v error -show_entries stream=index,codec_name,codec_type,duration -show_entries format=duration -of json INPUT`と同じコマンドの`OUTPUT`結果を保存して比較する。
- 期待する結果:
  - [ ] inspecting→extracting-audio→transcribing→building-cues→exporting→completedがJSON lineで出る
  - [ ] exit 0で、再生可能なMP4に日本語グリフがある
  - [ ] 出力videoの`codec_name`が`h264`、入力・出力ともaudio streamがちょうど1本（fixtureではAAC）ある
  - [ ] 入出力のformat duration差が1/15秒以内である
- readiness: 要設定(fixture-ja + ja-JP Speech model)
- 出典: `Sources/LocalSubCLI/main.swift:41-79`; `Sources/LocalSubApple/SubtitleVideoExporter.swift:13-98`

#### CLI-N-02 導入済みmodelで英語動画を日本語化できる
- ねらい: 非対話CLIの英語→日本語経路を確認する。
- 前提: en-US Speechとen→ja Translation modelが既に導入済み。合成英語MP4。
- 手順: 1. `fixtures/en-expected.txt`を読む。2. `--language english`で実行。3. JSON line、出力frame、数字・否定・固有名詞の意味を照合する。4. `swift test --scratch-path /tmp/localsub-tests --filter TranslationCorrelationTests`の生ログを保存する。
- 期待する結果:
  - [ ] translating stageを通り、exit 0になる
  - [ ] 出力は日本語で、数字・否定・固有名詞の意味が期待値に対応する
  - [ ] segment IDの欠落・重複拒否は映像から推測せず、`TranslationCorrelationTests`成功を一次証拠とする
- readiness: 要設定(fixture-en + 導入済みen-US/en→ja model)
- 出典: `Sources/LocalSubCLI/main.swift:57-69`; `Sources/LocalSubApple/AppleTranslationProvider.swift:11-28`

#### CLI-N-03 help相当のusageと分類済みexit codeを返す
- ねらい: 誤入力時に使い方を理解でき、成功と区別できる。
- 前提: なし。
- 手順: 1. `swift run ... localsub --help`。2. stderrとexit codeを記録。
- 期待する結果:
  - [ ] Usageが表示される
  - [ ] exit code 64で、成功0と区別される
- readiness: 今すぐ可
- 出典: `Sources/LocalSubCLI/main.swift:10-40,81-85`

#### CLI-N-04 Lunaと用語集で英語を自然な日本語へ変換できる
- ねらい: 非対話経路でも明示選択したLunaだけを使い、用語を固定する。
- 前提: en-US Speech、Luna利用可能なテストAPI project、`op-cached`でprocessへ注入するkey、32KiB以下の用語集、10秒以下の英語fixture。
- 手順: 1. CLIが表示するデータ送信・保持条件を確認する。2. 同意する場合だけ `op-cached secret exec --env OPENAI_API_KEY=<alias> -- localsub INPUT --output OUTPUT --language english --translation luna --acknowledge-luna-data-transfer --glossary terms.txt` を実行する。3. stage、字幕frame、出力有無を記録。4. request payloadの契約テストを併記する。
- 期待する結果:
  - [ ] translatingを通りexit 0、用語集・数字・否定・固有名詞を保持した自然な字幕になる
  - [ ] audio/video/path/filenameをResponses APIへ送らないことは映像から推測せず契約テストで確認する
  - [ ] key・transcript・provider本文をstderrへ出さない
- readiness: 要設定(GPT-5.6 Luna API project access)
- 出典: `Sources/LocalSubCLI/main.swift`; `Sources/LocalSubCloud/LunaTranslationProvider.swift`

## 異常系

#### CLI-E-01 非対応または音声なしmediaを変換前に拒否する
- ねらい: CLIがGUIと同じmedia policyを迂回しない。
- 前提: video-only MP4、WebMまたは非対応codec fixture。
- 手順: 1. 各入力で実行。2. stage、exit code、出力有無を確認。
- 期待する結果:
  - [ ] inspecting後に非0終了し、transcribing/exportingへ進まない
  - [ ] 完成名の出力を作らない
- readiness: 要設定(fixture-video-only/corrupt/WebM)
- 出典: `Sources/LocalSubCLI/main.swift:49-58`; `Sources/LocalSubApple/MediaInspector.swift:9-70`

#### CLI-E-02 未導入Speech/Translation modelを非対話で勝手に取得しない
- ねらい: CLIから同意なしのmodel downloadを始めない。
- 前提: en-US Speechまたはen→ja Translation model未導入端末。
- 手順: 1. 英語入力で実行。2. process/network/UI挙動とexit codeを記録。
- 期待する結果:
  - [ ] 対話許可UIを偽装せず非0終了する
  - [ ] 未導入modelを特定し、Desktopアプリで準備する案内を表示して完成名の出力を作らない
  - [ ] CLI processがAppleのmodel download APIを呼ばない
- readiness: 要設定(model未導入端末)
- 出典: `Sources/LocalSubCLI/main.swift`; `Sources/LocalSubApple/AppleSpeechTranscriber.swift`; `README.md:48-52`

#### CLI-E-03 既存出力・symlink・同時競合を上書きしない
- ねらい: batch実行でも他の成果物を破壊しない。
- 前提: 既存出力、symlink、同名へ同時実行する2process。
- 手順: 1. 既存hashを記録。2. 各競合を実行。3. hash、exit code、staging残骸を確認。
- 期待する結果:
  - [ ] 高々1processだけが新規公開し、既存/symlink先は不変
  - [ ] 失敗runは非0で完成名を作らない。所有性を証明できないstagingは自動削除せず記録する
- readiness: 要設定(fixture-ja + 既存/symlink/同時競合target)
- 出典: `Sources/LocalSubApple/SubtitleVideoExporter.swift:178-215`; `Sources/LocalSubApple/NonReplacingFileWriter.swift:5-45`

#### CLI-E-04 音声認識0件を成功出力にしない
- ねらい: 無音を完成字幕として扱わない。
- 前提: 対応codecの無音動画。
- 手順: 1. 実行。2. stderr、exit code、出力を確認。
- 期待する結果:
  - [ ] `No speech was recognized.`で非0終了する
  - [ ] 完成名のMP4を作らない
- readiness: 要設定(fixture-silent)
- 出典: `Sources/LocalSubCLI/main.swift:31-36,55-56`

#### CLI-E-05 Luna credential・model access・resource failureをfail-closedにする
- ねらい: batch利用時も費用・秘密・partial outputを制御する。
- 前提: keyなし、Luna未許可project、1,001 unit/総量超過・巨大応答は契約テストで用意。
- 手順: 1. 各条件でLuna実行。2. exit、stderr、request数、完成名の有無を確認。
- 期待する結果:
  - [ ] keyなし／model未許可は非0で、秘密やprovider本文を出さず完成名を作らない
  - [ ] request数・総入力上限超過はrequest開始前に拒否する
  - [ ] 2MiB超応答はstream受信中に中止し、複数batch途中の失敗でもpartial出力を公開しない
- readiness: 今すぐ可（live model未許可）＋自動契約テスト
- 出典: `Sources/LocalSubCloud/LunaTranslationProvider.swift`; `Tests/LocalSubCloudTests/LunaTranslationProviderTests.swift`

## 境界値

#### CLI-B-01 media policyの境界内外をGUIと同じく判定する
- ねらい: CLIだけが2時間・4K・60fps等の制限を迂回しない。
- 前提: `DSK-B-01`と同じfixture。
- 手順: 1. 境界内外を順に実行。2. inspecting後の結果を比較。
- 期待する結果:
  - [ ] 境界内は次stageへ進む
  - [ ] 超過はinspectingで非0終了し、出力しない
- readiness: 要設定(boundary fixtures)
- 出典: `Sources/LocalSubCLI/main.swift:49-58`; `Sources/LocalSubCore/MediaPolicy.swift:45-76`
