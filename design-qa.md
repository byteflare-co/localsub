# Design QA — 字幕style・表示時間

final result: passed

## 対象

- source truth: user-provided screenshot（3364x470、ephemeral attachment; not committed）
- implementation: local dogfood output（1920x1080、30.2秒、ignored by Git）
- focused comparison: local QA artifact（ignored by Git）
- full comparison: local QA artifact（ignored by Git）
- viewport/state: 元動画585–615秒、同時刻5/10/15/20/25秒。source screenshotとは発話内容が異なるため、sourceは配置意図、旧版と新版は同一stateの差分比較に使用した。

## Fidelity surfaces

| Surface | 判定 | 確認内容 |
|---|---|---|
| Typography | PASS | Hiragino Sans W6を維持し、1080pで56.16pxから48.6pxへ縮小。2行以内と全文表示をCoreTextで検証 |
| Alignment / spacing | PASS | 実glyph boundsを背景内で縦中央化。上下差4px以内のpixel testと同時刻frameで確認 |
| Caption pacing | PASS | 既定1行幅を全角約24字へ拡張し、短い完成文を約8秒まで結合。最大12秒・300文字・gap 1.2秒の上限は維持 |
| Preview / export parity | PASS | aspect-fit後の実動画座標を共有helperから算出。landscape/portrait相互のgeometry testを追加 |
| Colors / background | PASS | 白文字、黒72%背景、角丸を維持。映像自体の色変換なし |
| Copy / protected terms | PASS | Luna翻訳と用語保護を維持。長文化しても2行以内、表示不能時はclippingせずfail-closed |

## 比較履歴

1. 初期所見: 文字blockが背景上側に偏り、fontが大きく、短い字幕が頻繁に切り替わる。
2. 第1修正: CoreText中央配置、font縮小、表示容量と翻訳単位を拡張。
3. 敵対的レビュー: portraitで3行化、preview/export不一致、異常duration、極端な長文のsilent clippingを指摘。
4. 最終修正: adaptive縮小、visible range・行数検証、共有geometry、fail-closedを追加。
5. 第2調整: ユーザーの体感に合わせ、1行全角約20字から約24字、推奨6秒から8秒へ拡張。
6. 最終確認: 73 tests成功、30秒実動画を再生成。5地点のv10/v11比較で文字量増加と2行以内を確認。P0/P1/P2残件なし。

## 残る所見

- P3: 元動画に既存の英語・スペイン語字幕が焼き込まれている区間では、日本語字幕と視覚的に重なる。今回のstyle変更による回帰ではなく、将来の字幕位置profileで扱う。
- 全尺動画は今回のstyleではまだ再生成していない。短尺合格後に同じ設定で再生成する。
