# LocalSub Desktop 手動動作確認手順書

検証できないものを PASS にしない。前提未充足はスキップとして理由を記録する。
実行時は本書を `tmp/e2e-runs/<RUN_ID>/runbook-desktop.md` にコピーし、原本をチェックしない。

## fixture準備と共通cleanup

実在の会話を使わず、実行直前に次の要領で `RUN_DIR` 配下へ合成fixtureを作る。英語fixtureの期待値ファイルには、原文、期待する日本語の意味、数字 `42`、否定 `not`、固有名詞 `LocalSub`、発話時刻を記載する。

```sh
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="tmp/e2e-runs/$RUN_ID"
mkdir -p "$RUN_DIR/fixtures" "$RUN_DIR/evidence" "$RUN_DIR/output"
say -v Kyoko -o "$RUN_DIR/fixtures/ja.aiff" 'これはローカルサブの字幕テストです。合計は四十二です。'
say -v Samantha -o "$RUN_DIR/fixtures/en.aiff" 'LocalSub is not online. The total is 42.'
say -v Kyoko -r 500 -o "$RUN_DIR/fixtures/fast-long-ja.aiff" 'これは句読点を含まない非常に長い日本語字幕を短い時間で表示して二行分割と読む速度が速すぎるという警告を確実に確認するための合成音声テストです同じ画面から文字がはみ出さないことも確認します'
ffmpeg -f lavfi -i color=c=navy:s=1280x720:r=30:d=8 -i "$RUN_DIR/fixtures/ja.aiff" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$RUN_DIR/fixtures/ja.mp4"
ffmpeg -f lavfi -i color=c=darkgreen:s=1280x720:r=30:d=8 -i "$RUN_DIR/fixtures/en.aiff" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$RUN_DIR/fixtures/en.mp4"
ffmpeg -f lavfi -i color=c=purple:s=1280x720:r=30:d=8 -i "$RUN_DIR/fixtures/fast-long-ja.aiff" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$RUN_DIR/fixtures/fast-long-ja.mp4"
ffmpeg -f lavfi -i color=c=black:s=1280x720:r=30:d=8 -f lavfi -i anullsrc=r=48000:cl=stereo -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$RUN_DIR/fixtures/silent.mp4"
ffmpeg -f lavfi -i color=c=red:s=1280x720:r=30:d=8 -an -c:v libx264 -pix_fmt yuv420p "$RUN_DIR/fixtures/video-only.mp4"
ffmpeg -stream_loop -1 -i "$RUN_DIR/fixtures/ja.mp4" -t 45 -c copy "$RUN_DIR/fixtures/long-ja.mp4"
cp "$RUN_DIR/fixtures/long-ja.mp4" "$RUN_DIR/fixtures/long-ja-b.mp4"
ffmpeg -f lavfi -i color=c=navy:s=3840x2160:r=60:d=90 -stream_loop -1 -i "$RUN_DIR/fixtures/ja.aiff" -t 90 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$RUN_DIR/fixtures/cancel-4k60.mp4"
printf '%s\n' 'LocalSub is not online. -> LocalSubはオンラインではありません。' 'The total is 42. -> 合計は42です。' '発話順とおおよその時刻も実行時に記録する。' > "$RUN_DIR/fixtures/en-expected.txt"
head -c 256 "$RUN_DIR/fixtures/ja.mp4" > "$RUN_DIR/fixtures/corrupt.mp4"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$RUN_DIR/fixtures/long-ja.mp4"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$RUN_DIR/fixtures/cancel-4k60.mp4"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$RUN_DIR/fixtures/fast-long-ja.mp4"
```

fixture validity gateとして、`long-ja.mp4`が45秒、`cancel-4k60.mp4`が90秒、`fast-long-ja.mp4`が4秒以下であることを実行前に確認する。高速長文が4秒を超えた場合はrateを上げて再生成する。生成後の認識結果が80文字未満、読速警告なし、またはexportが取消操作前に完了した場合、その再現を必要とするケースはPASSにせず `INCONCLUSIVE (fixture insufficient)` とする。WebM、HDR、境界値、回転metadata fixtureは該当ケースで別途準備する。M4Vは実装上受理されるため非対応fixtureとして扱わない。各ケースの成果物は `RUN_DIR` 内だけに置き、証拠を保持した後は `RUN_DIR` をFinderのゴミ箱へ移す。bookmark cleanupはアプリを削除せず、テスト動画を移動して再選択状態を確認する。

## 正常系

#### DSK-N-01 sandboxed Desktopアプリが安心して起動できる
- ねらい: 初回画面、対応形式、privacy表示、署名境界を守る。
- 前提: macOS 26 / Apple Silicon。`./scripts/build-app.sh`成功済み。
- 手順: 1. `codesign --verify --deep --strict`を実行する。2. entitlementとRuntime Versionを読む。3. `.app`を開く。
- 期待する結果:
  - [ ] App Sandbox=true、user-selected read-write=true、network client=true、Hardened Runtimeあり
  - [ ] LocalSubの空状態と「動画を選ぶ」、MP4/MOV・SDR・4K・2時間、Luna時だけ英文を送る説明が読める
  - [ ] 980×680未満へ縮小されず、主要操作が欠けない
- readiness: 今すぐ可
- 出典: `Config/LocalSubApp.entitlements:1`; `scripts/build-app.sh:9-19`; `Sources/LocalSubApp/LocalSubApp.swift:313-336`

#### DSK-N-02 日本語動画から読める字幕付きMP4を作れる
- ねらい: ユーザーの主要ジャーニーを映像の末端まで確認する。
- 前提: ja-JP Speech利用可能。`say`で生成した日本語音声入りH.264/AAC MP4。
- 手順: 1. `fixtures/ja.mp4`を選ぶ。2. 日本語を選択し「字幕を生成」。3. 再生して字幕を確認。4. 字幕本文を1箇所修正。5. 「動画を書き出す」で空の保存先フォルダを選ぶ。6. 出力を再生し、cueの中央時刻を含むcontact sheetを保存する。7. `ffprobe -v error -show_entries stream=index,codec_name,codec_type,duration -show_entries format=duration -of json INPUT`と同じコマンドの`OUTPUT`結果を保存して比較する。
- 期待する結果:
  - [ ] 検査→音声準備→文字起こし→確認の進捗が表示される
  - [ ] previewの字幕本文・改行・表示時刻が音声と概ね一致し、修正が即時反映される
  - [ ] 出力MP4に白い日本語グリフと黒背景があり、背景だけの空字幕にならない
  - [ ] 出力videoの`codec_name`が`h264`、入力・出力ともaudio streamがちょうど1本（fixtureではAAC）ある
  - [ ] 入出力のformat duration差が1/15秒以内で、入力とは別ファイル
  - [ ] 出力失敗後も字幕を失わず、別フォルダを選んで再試行できる
  - [ ] 完了後に字幕を編集するとreviewへ戻り、再書き出しできる
- readiness: 要設定(fixture-ja + ja-JP Speech model)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:136-175,339-402`; `Sources/LocalSubApple/SubtitleVideoExporter.swift:13-175`

#### DSK-N-03 英語動画を意味の通る日本語字幕にできる
- ねらい: 英語認識・初回model準備・ID相関翻訳の連続経路を確認する。
- 前提: 合成英語MP4。en-US Speech利用可能。Apple model downloadは人間が承認した場合のみ。
- 手順: 1. `fixtures/en-expected.txt`を先に読み、`fixtures/en.mp4`を英語として生成する。2. 初回model許可UIが出た場合は判断を記録。3. 数字・否定・固有名詞の意味を期待値と照合し、1箇所編集する。4. MP4を書き出し再生する。5. `swift test --scratch-path /tmp/localsub-tests --filter TranslationCorrelationTests`の生ログを保存する。
- 期待する結果:
  - [ ] model準備中と翻訳中が区別され、UIが固まらない
  - [ ] UIでは数字、否定、固有名詞の意味が期待値に対応し、誤りは修正してから出力できる
  - [ ] segment IDの欠落・重複・順序混線の拒否はUI表示から推測せず、`TranslationCorrelationTests`成功を一次証拠とする
  - [ ] 焼き込み出力は修正後の日本語を表示する
- readiness: 要設定(fixture-en + en-US Speech + en→ja Translation model)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:155-218`; `Sources/LocalSubCore/Translation.swift:27-59`

#### DSK-N-04 2行字幕と読速警告を確認しながら本文を直せる
- ねらい: 長い日本語を画面外へ出さず、読めない速度を見落とさない。
- 前提: validity gateを通過した`fixtures/fast-long-ja.mp4`。
- 手順: 1. 字幕生成。2. 一覧とpreviewで長文cueを確認。3. 2行内で本文を修正。4. 警告の有無を確認。
- 期待する結果:
  - [ ] cueは最大2行で、一覧とpreviewに同じ本文が出る
  - [ ] 読速超過cueには「読む速度が速すぎます」が表示される
  - [ ] 空文字、3行目、制御文字は有効な字幕として確定しない
- readiness: 要設定(fixture-fast-long-ja)
- 出典: `Sources/LocalSubCore/CueBuilder.swift:27-61`; `Sources/LocalSubApp/LocalSubApp.swift:262-268,365-377`

#### DSK-N-05 UTF-8 SRTを別名で保存できる
- ねらい: 焼き込み以外の字幕資産を文字化け・暗黙上書きなしで得る。
- 前提: 1件以上の字幕生成済み。
- 手順: 1. 「SRT」を押して新規名を指定。2. UTF-8として開く。3. 番号、時刻、改行、本文をpreviewと照合する。
- 期待する結果:
  - [ ] `HH:MM:SS,mmm --> ...`形式で、日本語と改行が一致する
  - [ ] 既存SRTを選んでも暗黙置換されず、ユーザーに失敗が表示される
- readiness: 要設定(DSK-N-02で1件以上のcue生成済み)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:270-276,399-400`; `Sources/LocalSubCore/SRTSerializer.swift:3-24`

#### DSK-N-06 再起動後も最後に選んだ動画を安全に再検査する
- ねらい: bookmarkの再起動越しアクセスと再検査を確認する。
- 前提: DSK-N-02で動画を選択済み。
- 手順: 1. アプリを終了。2. 同じbundleを再起動。3. 動画が表示されるまで待つ。4. 元動画を移動した場合の挙動も別runで確認。
- 期待する結果:
  - [ ] 有効なbookmarkでは「動画を検査中」後にplayerと生成操作が戻る
  - [ ] 無効・移動済みbookmarkを成功扱いせず、失敗表示または再選択が必要になる
  - [ ] 字幕編集内容自体は復元されないことを既知ギャップとして記録する
- readiness: 要設定(DSK-N-02でbookmark作成済み)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:51-77,288-291`

#### DSK-N-07 Lunaを明示選択し用語どおりの自然な字幕にできる
- ねらい: 動画を送らず、明示同意した英文だけをLunaで自然な技術字幕へ翻訳する。
- 前提: en-US Speech、GPT-5.6 Lunaを利用できるテストAPI project、Keychainまたは`op-cached` process注入のkey、合成英語または許可済み10秒fixture。
- 手順: 1. 英語・GPT-5.6 Lunaを選ぶ。2. `Managed Agent=マネージドエージェント`等の用語集を入力。3. 生成を押し、確認文を読む。4. 一度キャンセルしてOpenAI通信がないことを記録。5. 再度同意して生成。6. 字幕とAPI requestの検査証拠を保存する。
- 期待する結果:
  - [ ] API keyはSecureFieldからKeychainへ保存でき、既存値を画面へ再表示しない
  - [ ] 確認文に動画・音声を送らないこと、英文・用語集を送ること、`store:false`、既定の監視ログ最大30日、暗号化prompt cache最大24時間、組織・project設定依存が表示される
  - [ ] 同意前はrequest 0件。同意後の送信先は`api.openai.com`だけで、payloadにmedia byte/path/filenameがない
  - [ ] 用語集を守り、数字・否定・固有名詞を保持し、直訳より自然な短い日本語になる
  - [ ] 設定は処理中に固定され、Apple開始jobが途中でLuna送信へ変わらない
- readiness: 要設定(GPT-5.6 Luna API project access)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift`; `Sources/LocalSubCloud/LunaTranslationProvider.swift`; `docs/architecture/decisions/006-optional-luna-cloud-translation.md`

## 異常系

#### DSK-E-01 非対応・破損・音声なし動画を早期に拒否できる
- ねらい: 危険または処理不能なmediaを認識処理へ流さない。
- 前提: WebM、壊れたMP4、video-only MP4、HDRまたは非対応codec fixture。
- 手順: 1. 各fixtureを選ぶ。2. 状態と操作可否を記録。3. 続けて正常動画を選ぶ。
- 期待する結果:
  - [ ] 理由のある失敗表示になり、「字幕を生成」は有効にならない
  - [ ] アプリがcrash/hangせず、正常動画の再選択で復旧する
- readiness: 要設定(fixture-video-only/corrupt/WebM/HDR)
- 出典: `Sources/LocalSubApple/MediaInspector.swift:9-70`; `Sources/LocalSubApp/LocalSubApp.swift:120-132`

#### DSK-E-02 無音・認識0件の現行ギャップを誤って成功扱いしない
- ねらい: 字幕がない結果を完成と誤認しない。
- 前提: 対応codecの無音音声トラック付きMP4。
- 手順: 1. 動画を選び生成。2. cue件数、status、export可否を確認。
- 期待する結果:
  - [ ] cue 0件ではMP4/SRT書出しが有効にならない
  - [ ] 明示的な「音声を認識できない」エラーがない現状は PASS ではなく既知ギャップとして記録する
- readiness: 要設定(fixture-silent)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:79-81,163-166,362-364`

#### DSK-E-03 取消後に古い字幕や出力が混入しない
- ねらい: 長時間処理の取消・動画切替・late resultを隔離する。
- 前提: `fixtures/long-ja.mp4`、`long-ja-b.mp4`、export取消用`cancel-4k60.mp4`。出力先は新規名。
- 手順: 1. Aを生成中に取消。2. 「キャンセル中」が終わるまで待つ。3. Bを選んで生成。4. `cancel-4k60.mp4`のexport中にも取消。5. 出力先と字幕を確認。6. 取消操作前に処理が完了した場合はPASSにせず`INCONCLUSIVE`と記録する。
- 期待する結果:
  - [ ] 取消完了前に新しい生成が始まらず、完了後は操作可能になる
  - [ ] Aの字幕・翻訳がBへ現れない
  - [ ] export取消後に完成名のMP4が新規公開されない。残ったstagingは別fileを誤削除しないため自動cleanupせず記録する
- readiness: 要設定(fixture-long-ja/long-ja-b/cancel-4k60)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:96-134,177-259`; `Sources/LocalSubApple/SubtitleVideoExporter.swift:72-82,178-215`

#### DSK-E-04 既存出力やsymlinkを暗黙上書きしない
- ねらい: 保存先の競合で他ファイルを壊さない。
- 前提: 同名既存MP4/SRT。symlink攻撃はUIでなくintegration testを一次証拠とする。
- 手順: 1. Save panelで既存名を選ぶ。2. 既存内容のhashを前後比較。3. 新規名で再試行。
- 期待する結果:
  - [ ] 既存内容は変わらず、LocalSubは失敗を表示する
  - [ ] 新規名では成功する
  - [ ] symlink拒否は自動統合テストの結果を併記し、UIだけで再現したと記録しない
- readiness: 要設定(DSK-N-02出力 + 既存ファイルfixture)
- 出典: `Sources/LocalSubApple/NonReplacingFileWriter.swift:5-45`; `Tests/LocalSubAppleIntegrationTests/SubtitleVideoExporterTests.swift`

#### DSK-E-05 model準備拒否・offlineから安全に戻れる
- ねらい: Apple modelが利用できないときに無限待ちや誤字幕を作らない。
- 前提: 未導入modelの端末、または人間が許可UIを拒否できる状態。
- 手順: 1. 英語生成。2. model導入を拒否またはofflineにする。3. error/statusと取消を確認。4. 日本語の正常動画へ切替。
- 期待する結果:
  - [ ] 英語字幕を捏造せず、失敗または取消として止まる
  - [ ] 日本語動画へ切り替えると復旧する
- readiness: 要設定(model未導入端末)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:17-19,155-218,241-259`

#### DSK-E-06 ad-hoc buildを配布可能と誤認しない
- ねらい: local dogfoodとDeveloper ID配布候補の品質gateを分離する。
- 前提: local bundle。release確認にはDeveloper ID/notary profileが必要。
- 手順: 1. local bundleの`codesign -dvv`と`spctl`を記録。2. 資格情報がある場合のみrelease scriptを実行。
- 期待する結果:
  - [ ] local bundleはRuntimeあり・ad-hoc・TeamIdentifierなし・Gatekeeper rejectedとして記録する
  - [ ] release buildはnotarize、staple、`spctl`の全成功がない限りPASSにしない
- readiness: local確認は今すぐ可 / releaseは要設定(Developer ID + notary profile)
- 出典: `scripts/build-app.sh:9-19`; `scripts/build-release.sh:1-22`

#### DSK-E-07 Lunaのkey・権限・通信・応答異常を黙って成功扱いしない
- ねらい: cloud失敗で誤字幕や意図しないApple fallbackを作らない。
- 前提: keyなし、Luna未許可project、offline、invalid structured responseは順に独立runまたは自動契約テストで作る。
- 手順: 1. 各条件でLuna生成。2. status、request数、cue、完成出力を確認。3. Appleへ自動切替されないことを確認。
- 期待する結果:
  - [ ] keyなしでは文字起こし前に設定sheetが開き、通信しない
  - [ ] `model_not_found`は利用不可と表示し、HTTP本文やproject情報、keyを表示しない
  - [ ] network/timeout/oversize/schema/ID異常は失敗し、partial cueや完成出力を作らない
  - [ ] Appleへ黙ってfallbackせず、ユーザーが方式を選び直せる
- readiness: keyなし・未許可projectは今すぐ可 / 応答注入は自動契約テスト
- 出典: `Sources/LocalSubCloud/LunaTranslationProvider.swift`; `Tests/LocalSubCloudTests/LunaTranslationProviderTests.swift`

## 境界値

#### DSK-B-01 media上限の内外を区別する
- ねらい: 4K・2時間・60fps・8ch/192kHz等の境界を一貫して扱う。
- 前提: 4K短尺60fps正常fixture、61fps/超4K/多track等の拒否fixture。2時間はAPI fixture代替可。
- 手順: 1. 境界内外を選ぶ。2. 正常はready、超過はfailedになることを確認。
- 期待する結果:
  - [ ] 境界内の対応mediaは生成可能になる
  - [ ] 1項目でも超過したmediaは理由付きで拒否される
- readiness: 要設定(boundary fixtures)
- 出典: `Sources/LocalSubCore/MediaPolicy.swift:45-76`; `Tests/LocalSubCoreTests/MediaPolicyTests.swift`

#### DSK-B-02 長い日本語でも2行・画面内を保つ
- ねらい: 文字切れ、3行化、制御文字混入を防ぐ。
- 前提: validity gateを通過した`fixtures/fast-long-ja.mp4`。
- 手順: 1. 生成。2. 最大長cueをpreview/一覧/出力frameで比較。
- 期待する結果:
  - [ ] 2行以内で、左右端と下端から安全余白がある
  - [ ] previewと出力で本文・改行・フォントの見え方が一致する
- readiness: 要設定(fixture-fast-long-ja)
- 出典: `Sources/LocalSubCore/CueBuilder.swift:62-112`; `Sources/LocalSubApple/SubtitleVideoExporter.swift:100-175`

#### DSK-B-03 横・縦・回転metadata動画で字幕位置を保つ
- ねらい: preferred transform適用後も字幕が画面外へ出ない。
- 前提: 16:9、9:16、90度回転metadata付きfixture。
- 手順: 1. 各動画で生成・preview。2. MP4出力。3. 指定時刻frameを比較。
- 期待する結果:
  - [ ] 映像の向きと解像度が正しく、字幕が下部安全領域にある
  - [ ] previewと出力frameに同じ日本語グリフがある
- readiness: 要設定(aspect/rotation fixtures)
- 出典: `Sources/LocalSubApple/SubtitleVideoExporter.swift:18-64,100-175`; `Sources/LocalSubApp/LocalSubApp.swift:339-351,462-482`

#### DSK-B-04 キーボードとVoiceOverで主要導線を把握できる
- ねらい: mouseだけに依存せず、内部IDを利用者へ露出しない。
- 前提: VoiceOver利用可能。
- 手順: 1. Tab/Shift-Tabと⌘Oで操作。2. VoiceOverでempty、picker、生成、字幕一覧、exportを読む。
- 期待する結果:
  - [ ] 主要操作に到達でき、意味のある日本語ラベルが読まれる
  - [ ] cue内部IDやURL生値をユーザーラベルとして読まない
  - [ ] 字幕行の時刻/警告/編集欄の読み分け不足は改善提案として記録する
- readiness: 要設定(DSK-N-02で字幕一覧生成済み + VoiceOver)
- 出典: `Sources/LocalSubApp/LocalSubApp.swift:308-414`
