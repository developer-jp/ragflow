# 日本語用語辞書の更新方法

このプロジェクトで利用する `huqie.txt` は、日本語の一般語彙と空調系ドメイン語彙から構成されます。以下のスクリプトでソースを取得し、`rag/res/` 配下の辞書を再生成できます。

```bash
python3 scripts/build_huqie_jp.py
```

## 生成されるファイル

- `rag/res/huqie_ja_general.txt` : mecab-ipadic-NEologd の seed を加工した一般語彙。
- `rag/res/huqie_ja_hvac.txt` : オリオン機械の空調用語集を抽出した語彙。
- `rag/res/huqie.txt` : 上記ファイルをマージした最終辞書。`RagTokenizer` はこのファイルを読み込みます。
- `rag/res/huqie.txt.trie` : スクリプト実行時に削除され、起動時に自動再生成されます。

## オプション

スクリプトは念のため CLI オプションも用意しています。例:

- `--max-entries 300000` : 一般語彙の上限件数を調整。
- `--min-freq 50` : MeCab コストから計算した頻度が閾値未満の語を除外。
- `--no-aggregate` : 中間ファイルのみを生成。
- `--skip-hvac` : 一時的に HVAC 用語集をスキップ。

詳細は `python3 scripts/build_huqie_jp.py --help` を参照してください。

## 元データ

- 一般語彙: [mecab-ipadic-NEologd seed CSV](https://github.com/neologd/mecab-ipadic-neologd/blob/master/seed/mecab-user-dict-seed.20200910.csv.xz)
- 空調用語: [オリオン機械 空調用語集](https://www.orionkikai.co.jp/technology/pap/dictionary/)

各データは MIT ライセンスまたはサイト記載の条件に基づいて利用しています。再配布ポリシーに注意してください。
