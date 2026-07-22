# 文字起こし / Mojiokosi Simple

Windows 11 の「ライブ キャプション」が認識した音声を、文字だけのシンプルなウィンドウへリアルタイム表示し、UTF-8 のテキストファイルへ自動保存するソフトです。

Mojiokosi Simple displays text recognized by Windows 11 Live Captions in a clean, text-only window and automatically saves it as a UTF-8 text file.

[日本語](#japanese) | [English](#english)

> [!IMPORTANT]
> **GitHub からソフト本体は再ダウンロードできますが、あなたの文字起こしファイルは復元できません。**
> `transcripts` フォルダーはプライバシー保護のため GitHub の対象外です。PC の故障・紛失・買い替えに備え、必ず別のドライブ、外付け媒体、または信頼できるクラウドストレージへバックアップしてください。
>
> **You can download the app again from GitHub, but GitHub cannot restore your transcripts.**
> The `transcripts` folder is intentionally excluded from Git. Back it up separately to another drive, external storage, or a trusted cloud service.

---

<a id="japanese"></a>

# 日本語

## このソフトについて

画面に出る操作ボタンは、終了用の `×` だけです。設定画面、録音ボタン、開始・停止ボタンなどはありません。デスクトップの `文字起こし` ショートカットを開くと処理が始まり、PC で再生している動画、会議、配信などの音声が文字として表示されます。

主な特徴:

- Windows 11 標準の「ライブ キャプション」を音声認識エンジンとして使用
- 文字だけを表示する、黒背景のシンプルな画面
- 見えるボタンは閉じる `×` だけ
- ウィンドウの移動、自由なサイズ変更、半分・4分の1へのスナップに対応
- `Win + 矢印`、複数モニター間の移動、縦長画面向け配置に対応
- 全画面表示、スクロール、文字選択・コピーに対応
- 常に最前面には固定されず、ブラウザなどの後ろにも移動可能
- 文字起こしを起動ごとに別の UTF-8 テキストへ自動保存
- API キー、Python、Node.js、外部の文字起こしサービスは不要
- インストーラー形式ではなく、PowerShell スクリプトだけで動作

## 仕組み

```text
PC で再生している音声
        ↓
Windows 11 ライブ キャプション
  （Windows が端末内で音声認識）
        ↓
このソフトが表示文字を Windows UI Automation で取得
        ├─ シンプルな文字画面へ表示
        └─ transcripts フォルダーへ保存
```

音声認識モデルそのものはこのリポジトリ独自のものではありません。認識は Windows 11 のライブ キャプションが担当し、このソフトはライブ キャプションの文字を取得・整理して、専用画面へ表示・保存します。

Microsoft は、必要な言語ファイルを最初にダウンロードした後、ライブ キャプションの音声と字幕生成は端末上で処理され、音声・音声データ・字幕は Microsoft やクラウドへ送信されないと説明しています。このソフトのスクリプトにも、音声や文字を外部へアップロードする処理はありません。

認識精度は、話し方、音質、雑音、複数人の同時発話、PC の負荷、Windows の更新などで変わります。「世界最高レベル」などの保証はしていません。実際に使う動画や会議で確認してください。

Microsoft 公式情報: [Windows でライブ キャプションを使用する](https://support.microsoft.com/ja-jp/accessibility/windows/use-live-captions-to-better-understand-audio)

## 必要なもの

| 項目 | 内容 |
| --- | --- |
| OS | Windows 11 バージョン 22H2 以降 |
| 音声認識 | Windows の「ライブ キャプション」と、使用する言語の音声認識パック |
| PowerShell | Windows PowerShell 5.1（Windows 11 に標準搭載） |
| 権限 | 通常は管理者権限不要 |
| インターネット | ソフトのダウンロードと、初回の言語ファイル取得時に必要。設定完了後の認識は端末内で動作 |

Windows 10、macOS、Linux には対応していません。

## 新しいPCへの最短セットアップ

### 1. ソフトをダウンロードする

[GitHub のリポジトリ](https://github.com/tghcgu/mojiokosi-simple)を開き、緑色の **Code** → **Download ZIP** を選びます。

直接ダウンロード: [main ブランチの ZIP](https://github.com/tghcgu/mojiokosi-simple/archive/refs/heads/main.zip)

Git を使える場合は、次でも取得できます。

```powershell
git clone https://github.com/tghcgu/mojiokosi-simple.git
```

### 2. ZIPを完全に展開する

ダウンロードした ZIP を右クリックして **すべて展開** を選びます。ZIP の中から直接実行しないでください。

GitHub の ZIP は通常 `mojiokosi-simple-main` という名前で展開されます。`mojiokosi-simple` などへ名前を変える場合は、ショートカットを作る**前**に変更してください。

展開方法によっては同じような名前のフォルダーが二重になります。`README.md` と `.app` が入っている内側のフォルダーが本体です。そのフォルダーを開いた状態で、以降のコマンドを実行します。

展開したフォルダーを、今後も消したり移動したりしない場所へ置きます。例:

```text
C:\Users\<あなたのユーザー名>\Documents\mojiokosi-simple
```

次の点に注意してください。

- `Program Files` など、通常ユーザーが書き込みにくい場所は避ける
- デスクトップのショートカットを作った後にフォルダー名や保存場所を変えない
- クラウド同期フォルダーへ置く場合も、同期が完了しているか自分で確認する
- このソフト自身にはクラウドバックアップ機能がない

ショートカットにはスクリプトの**絶対パス**が保存されます。後からフォルダーを移動・改名した場合は、移動後の場所でセットアップをもう一度実行してください。

### 3. セットアップを実行する

上で確認した本体フォルダー（`README.md` と `.app` が入っている内側）をエクスプローラーで開きます。

簡単な開き方:

1. エクスプローラー上部のアドレス欄をクリック
2. `powershell` と入力して Enter
3. 開いた青または黒の画面へ次を貼り付けて Enter

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

Windows 11 の **ターミナルで開く** を使って、そのフォルダーから PowerShell を開いても構いません。

実行すると:

- デスクトップに `文字起こし` ショートカットが1つ作成される
- 保存用の `transcripts` フォルダーが作成される
- このソフトの古い開始・停止ショートカットがあれば整理される

アプリ本体が別の場所へコピーされるわけではありません。展開したフォルダーが、そのまま本体です。削除するとショートカットは動かなくなります。

`-ExecutionPolicy Bypass` は、この1回の PowerShell プロセスでスクリプトを実行できるようにする指定です。PC 全体の実行ポリシーを永続変更するものではありません。

### 4. 初回起動とWindowsの初期設定

1. デスクトップの `文字起こし` をダブルクリック
2. Windows のライブ キャプション初期設定が表示されたら、案内に従う
3. 使用する言語（日本語など）の音声認識ファイルをダウンロード
4. 設定完了後、動画などを再生して文字が出ることを確認
5. 右上の `×` で終了
6. `transcripts` に新しい `.txt` ファイルがあることを確認

言語ファイルの初回ダウンロードにはインターネット接続が必要です。

## 普段の使い方

1. デスクトップの `文字起こし` を開く
2. PC で動画、会議、配信などの音声を再生する
3. 認識された文字が自動で表示される
4. 終わったら右上の `×`、`Esc`、または `Alt + F4` で閉じる

起動時にライブ キャプションを新しく開始するため、既に手動で開いていたライブ キャプションは閉じて再起動されることがあります。

同時に起動できる文字起こし画面は1つだけです。既に動いている状態でショートカットをもう一度開いても、2つ目は起動しません。

## 画面操作

| やりたいこと | 操作 |
| --- | --- |
| ウィンドウを移動 | 画面上部または外側の空いている余白をドラッグ |
| 自由にサイズ変更 | 四辺または四隅をドラッグ |
| 左右半分に配置・隣の画面へ進む | 上部の余白を画面の左端・右端へドラッグ、または `Win + ← / →`。同じ方向を繰り返すと、画面の端から隣接モニターへ進む |
| 配置をできるだけ保って隣の画面へ直接移動 | `Win + Shift + ← / →`。縦横の向きが異なる場合は、移動方向と移動先に合う配置へ自動調整 |
| 4分の1に配置 | 上部の余白を画面の四隅へドラッグ、または左右半分の後に `Win + ↑ / ↓`。縦長画面では細くなりすぎないよう、全幅の上半分・下半分になる |
| 最大化 | 上部の余白を画面上端中央へドラッグ、または `Win + ↑` |
| 元のサイズへ戻す | スナップ中に上部の余白を画面中央へドラッグ。キー操作では、最大表示なら `Win + ↓`、左右半分・4分の1なら状態に応じて `Win + ↓` を繰り返す |
| 全画面表示 | `F11`、または上部の余白をダブルクリック。同じ操作で元に戻る |
| 最小化 | 通常サイズの状態で `Win + ↓` |
| 過去の文字を見る | マウスホイール、右側のスクロールバー、キーボード |
| 文字をコピー | 文字を選択して `Ctrl + C` |
| 終了 | 右上の `×`、`Esc`、または `Alt + F4` |

`Win + 矢印` は、文字起こし画面が選択されている時に動作します。左右どちらの Windows キーでも使えます。モニターはWindows上の座標と位置関係から選ばれるため、左右の高さがずれた配置や解像度の異なる画面にも対応します。隣のモニターがない方向では、現在の画面端に留まります。

横長モニターでは四隅が4分の1表示になります。縦長モニターでは、四隅へのドラッグ、または左右半分からの `Win + ↑ / ↓` が全幅の上半分・下半分になり、文字欄が細長くなりすぎるのを防ぎます。左右半分の配置も引き続き使用できます。高い表示倍率などで画面が非常に細く、最小サイズを保ったまま分割できない場合は、画面外にはみ出さない配置へ自動的に切り替わります。

最新行を見ている間は、新しい文字へ自動で追従します。上へスクロールして過去の行を読んでいる間や文字を選択している間は、可能な限り表示位置と選択範囲を保ちます。

最新行の下には表示専用の1行分の余白を確保し、一番下の文字が途中で切れないようにします。この余白は保存される文字起こしファイルには入りません。

この画面は常に最前面ではありません。ブラウザなど別のアプリをクリックするか `Alt + Tab` で切り替えると、そのアプリの後ろへ移動します。複数モニターでも使用できます。

## 保存されるファイル

起動するたび、プロジェクト直下の `transcripts` に新しいテキストファイルが作られます。

```text
mojiokosi-simple\
├─ .app\
├─ transcripts\
│  ├─ caption-20260720-090000-123.txt
│  └─ caption-20260720-101530-456.txt
├─ .gitignore
└─ README.md
```

ファイル名:

```text
caption-YYYYMMDD-HHMMSS-milliseconds.txt
```

保存仕様:

- 文字コードは UTF-8
- 時刻は起動したPCのローカル時刻
- 起動1回につき1ファイル
- 認識中も同じファイルへ継続的に反映
- 正常終了時に最新内容をもう一度保存
- 認識できる発話がなければ空のファイルになる場合がある
- 古いファイルは自動削除されない
- 音声ファイルは保存されず、文字だけが保存される

保存のたびにファイル全体を書き直すため、書き込み中に突然の電源断やドライブ故障が起きると、最後の文字だけでなくファイル全体が不完全になる可能性があります。重要な用途では、終了後に保存ファイルを確認し、早めに別媒体へコピーしてください。

## 絶対に必要なバックアップ

`transcripts` は `.gitignore` に登録され、通常のGit操作ではコミット対象にならないため、GitHubには保存されません。これは会議や動画の内容を誤って公開しないための仕様です。ただし、強制追加など特殊な操作をした場合まで防ぐものではありません。

おすすめのバックアップ手順:

1. 文字起こし画面を `×` で閉じる
2. プロジェクト内の `transcripts` フォルダーを丸ごとコピー
3. 別の物理ドライブ、外付けSSD/USB、NAS、または信頼できるクラウドへ保存
4. バックアップ先のファイルを実際に開けることを確認
5. 定期的に繰り返す

同じPC内の別フォルダーだけでは、PC本体やドライブが壊れた時に一緒に失われます。少なくとも1つは別の機器または信頼できるオンライン保存先に置いてください。

文字起こしには個人情報や機密情報が含まれる可能性があります。保存先のアクセス権、共有設定、暗号化は利用者が管理してください。

## PCが壊れた・買い替えた時の復旧

### バックアップがある場合

1. 新しいPCを Windows Update で最新状態にする
2. このREADMEの「新しいPCへの最短セットアップ」に従い、GitHubから最新版を取得
3. ZIPを完全に展開し、今後動かさない場所へ置く
4. バックアップしていた `transcripts` フォルダーを、新しいプロジェクト直下へコピー
5. 新しい場所で `Install-Shortcuts.ps1` を実行
6. デスクトップの `文字起こし` を開く
7. Windowsから求められた場合は言語ファイルを再ダウンロード
8. 短い音声で表示と新規ファイル保存を確認
9. 過去の文字起こしファイルも開けることを確認

### バックアップがない場合

ソフト本体は GitHub から再取得できますが、古い `transcripts` は GitHub に存在しないため、このリポジトリからは復旧できません。壊れた旧ドライブからのデータ救出が必要になります。

## 更新・フォルダー移動

安全な更新方法:

1. 文字起こしを終了する
2. 旧フォルダーの `transcripts` を別の場所へバックアップ
3. GitHubから新しいZIPをダウンロード
4. 新しい別フォルダーへ完全に展開
5. バックアップした `transcripts` を新しいフォルダー直下へコピー
6. 新しいフォルダーでセットアップコマンドを実行
7. デスクトップのショートカットから起動し、新しい保存ファイルを確認
8. 問題がないことを確認してから旧フォルダーを削除

フォルダーを移動・改名しただけの場合も、移動後のフォルダーで次を再実行してください。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

セットアップは新しい絶対パスを使ってデスクトップのショートカットを作り直します。

## トラブルシューティング

### ショートカットを開いても何も起きない

- 既に文字起こし画面が開いていないか、`Alt + Tab` やタスクバーで確認
- フォルダーを移動・改名していないか確認
- 移動した場合は、その場所でセットアップコマンドを再実行
- `Program Files` や読み取り専用の場所ではなく、書き込み可能なフォルダーへ置く

手動起動すると、PowerShellにエラーが表示される場合があります。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\.app\Start-LiveCaptionsToNotepad.ps1
```

### Windowsライブ キャプション自体を確認する

まず `Win + Ctrl + L` を押し、Windows標準のライブ キャプションが単独で起動するか確認してください。

- 起動しない: Windows Update、ライブ キャプションの対応状況、Windowsの設定を確認
- 初期設定が出る: 案内に従って言語ファイルをダウンロード
- 標準画面でも認識しない: このソフトではなく、Windows側の音声出力・言語・認識環境を確認

### 「Windows ライブ キャプションを開始できません」と出る

`Win + Ctrl + L` で標準機能が起動するか確認し、PCを再起動してもう一度試してください。Windows 11が22H2以降で、Windows Updateが完了していることも確認します。

### 「初期設定を完了してください」と出る

表示されたWindowsの案内に従って、使う言語の音声認識ファイルをインストールしてください。完了後、一度画面を閉じて `文字起こし` を開き直します。

### 画面は出るが文字が出ない

- PCから実際に音が出ているか確認
- Windowsの既定の出力デバイスを確認
- BluetoothイヤホンやHDMIモニター使用時は、その機器が既定の出力になっているか確認
- 再生音声とライブ キャプションの認識言語を合わせる
- `Win + Ctrl + L` で標準ライブ キャプションでも認識するか確認
- 音量、話者の声、雑音、PC負荷を確認

音声入力元はWindowsライブ キャプションが管理します。通常、ライブ キャプションのマイクはオフで始まりますが、このソフトがマイクを技術的に固定・禁止しているわけではありません。Windows側でマイク入力が有効なら、その音声も対象になる可能性があります。

### 文字が遅い・誤認識・重複・抜けがある

このソフトは変化するライブ キャプション表示を随時取り込み、重複や途中修正をできるだけ整理します。それでも、次の条件では遅延、誤認識、重複、抜けが発生する場合があります。

- 背景音や音楽が大きい
- 複数人が同時に話す
- 音が小さい、途切れる、圧縮で劣化している
- PCのCPUやメモリ負荷が高い
- Windowsライブ キャプションの表示仕様が更新された

歌詞、音楽、拍手などの非音声イベントは、正確な文字起こしを保証できません。

### ウィンドウがブラウザの後ろへ行く

正常な動作です。常に最前面に固定しない設計のため、選択したアプリが前に出ます。`Alt + Tab` またはタスクバーから文字起こし画面へ戻れます。

### ウィンドウが見つからない・画面外へ行った

- `Alt + Tab` で文字起こしを選び、`Win + ↑` を押す
- 複数モニターの接続状態を元に戻して確認
- 一度終了して再起動する

### 保存ファイルが作られない

- プロジェクトフォルダーが書き込み可能か確認
- フォルダーを読み取り専用媒体や保護された場所へ置いていないか確認
- セキュリティソフトの履歴を確認
- 手動起動コマンドでエラーを確認

### PowerShellに実行拒否・ブロックが表示される

ダウンロードしたファイルへWindowsのブロックが付いている場合は、プロジェクトフォルダーで次を実行してから、セットアップをやり直します。

```powershell
Unblock-File .\.app\Install-Shortcuts.ps1
Unblock-File .\.app\Start-LiveCaptionsToNotepad.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

出所を確認できないスクリプトには `Unblock-File` を使わないでください。このリポジトリのURLとダウンロード元を確認してから実行します。

## 保存先を手動で変更する（上級者向け）

デスクトップショートカットを使わずに起動する場合は、`-OutputDirectory` で保存先を指定できます。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\.app\Start-LiveCaptionsToNotepad.ps1 -OutputDirectory "D:\Transcripts"
```

指定先が存在しなければ、作成できる場所では自動作成されます。この指定は、その手動起動にだけ適用されます。通常のデスクトップショートカットは引き続きプロジェクト直下の `transcripts` を使います。

## アンインストール

専用のアンインストーラーはありません。次の順序で削除できます。

1. 文字起こし画面を閉じる
2. 必要な `transcripts` を別の場所へバックアップ
3. デスクトップの `文字起こし` ショートカットを削除
4. 展開した本体フォルダー（`README.md` と `.app` が入っているフォルダー）を削除

このソフトはサービス、スタートアップ項目、スケジュールタスク、専用レジストリ設定を追加しません。Windowsが管理するライブ キャプションの言語ファイルは、この手順では削除されません。

> [!CAUTION]
> プロジェクトフォルダーを削除すると、中の `transcripts` も一緒に削除されます。先にバックアップを確認してください。

## プライバシーとセキュリティ

- 認識処理はWindowsライブ キャプションが担当
- 初回セットアップではMicrosoftから言語ファイルをダウンロード
- 言語ファイル取得後の音声認識は、Microsoftの説明では端末上で処理
- このソフトは音声を録音ファイルとして保存しない
- このソフトのスクリプトは音声や文字を外部APIへ送信しない
- 文字起こし結果は暗号化されていない通常のテキストファイル
- `transcripts` はGitHubには含まれないが、OS、同期ソフト、バックアップソフト、他のユーザーから見える可能性がある

機密会議、個人情報、医療・法律・金融など重要な内容では、利用組織の規則と保存方針を確認し、必ず原音や公式記録と照合してください。

## 制限事項

- Windowsライブ キャプションの認識精度を超えるものではない
- 完全な逐語記録や法的な議事録を保証しない
- 誤認識、欠落、重複、句読点の違いが発生しうる
- Windows Updateでライブ キャプションの画面構造が変わると、文字取得が動かなくなる可能性がある
- ライブ キャプションを既に手動利用している場合、アプリ起動時に閉じて再起動することがある
- 古い文字起こしの自動整理・削除・クラウド同期は行わない
- ソフトの自動更新機能はない

## フォルダー構成

```text
mojiokosi-simple\
├─ .app\
│  ├─ Install-Shortcuts.ps1
│  └─ Start-LiveCaptionsToNotepad.ps1
├─ transcripts\                 # 初回セットアップまたは起動時に作成
├─ .gitignore
└─ README.md
```

- `Install-Shortcuts.ps1`: デスクトップショートカットを作成
- `Start-LiveCaptionsToNotepad.ps1`: ライブ キャプションの起動、文字取得、画面表示、保存を担当
- `transcripts`: 利用者の文字起こし保存先。GitHub対象外

## 困った時

不具合を報告する場合は、[GitHub Issues](https://github.com/tghcgu/mojiokosi-simple/issues) を使用できます。公開して問題のない範囲で、次を添えると原因を確認しやすくなります。

- Windows 11のバージョン
- 認識言語
- どの操作で問題が起きたか
- 表示されたエラーメッセージ
- `Win + Ctrl + L` で標準ライブ キャプションが動くか

文字起こし本文や機密情報はIssueへ貼らないでください。

---

<a id="english"></a>

# English

## About this app

The only visible button is the close `×` button. There is no settings screen, record button, or separate start/stop control. Open the desktop shortcut named `文字起こし`, play audio from a video, meeting, stream, or another app, and recognized text appears automatically.

Key features:

- Uses Windows 11 Live Captions as the speech-recognition engine
- Shows a clean text-only window with a black background
- Displays only one button: close `×`
- Supports moving, free resizing, half-screen snapping, and quarter-screen snapping
- Supports `Win + Arrow`, movement across monitors, and portrait-aware layouts
- Supports full screen, scrolling, text selection, and copying
- Is not forced always-on-top, so browsers and other apps can cover it
- Saves each launch to a separate UTF-8 text file
- Requires no API key, Python, Node.js, or external transcription service
- Runs from PowerShell scripts; there is no traditional installer package

## How it works

```text
Audio playing on the PC
        ↓
Windows 11 Live Captions
  (Windows performs on-device speech recognition)
        ↓
This app reads displayed text through Windows UI Automation
        ├─ Displays it in a simple text window
        └─ Saves it in the transcripts folder
```

The speech-recognition model is not original to this repository. Windows 11 Live Captions performs recognition. This app retrieves and organizes the displayed captions, then presents and saves them in a simpler interface.

Microsoft states that after the required language files have been downloaded, Live Captions processes audio and generates captions on the device, and audio, voice data, and captions are not sent to Microsoft or the cloud. The scripts in this repository also contain no code that uploads audio or text to an external service.

Accuracy varies with speech, audio quality, background noise, overlapping speakers, PC load, and Windows updates. This project does not claim “world-best” accuracy. Test it with the actual content you intend to use.

Official Microsoft information: [Use live captions to better understand audio](https://support.microsoft.com/en-us/accessibility/windows/use-live-captions-to-better-understand-audio)

## Requirements

| Item | Requirement |
| --- | --- |
| OS | Windows 11 version 22H2 or later |
| Speech recognition | Windows Live Captions and a speech-recognition pack for the language you use |
| PowerShell | Windows PowerShell 5.1, included with Windows 11 |
| Permissions | Administrator access is normally not required |
| Internet | Required to download the app and the language files initially. Recognition runs on-device after setup |

Windows 10, macOS, and Linux are not supported.

## Fast setup on a new PC

### 1. Download the app

Open the [GitHub repository](https://github.com/tghcgu/mojiokosi-simple), select the green **Code** button, and choose **Download ZIP**.

Direct download: [ZIP of the main branch](https://github.com/tghcgu/mojiokosi-simple/archive/refs/heads/main.zip)

If Git is already installed, you may clone it instead:

```powershell
git clone https://github.com/tghcgu/mojiokosi-simple.git
```

### 2. Fully extract the ZIP

Right-click the downloaded ZIP and choose **Extract All**. Do not run the scripts from inside the ZIP.

GitHub normally extracts the folder as `mojiokosi-simple-main`. If you want to rename it to `mojiokosi-simple` or another name, do so **before** creating the shortcut.

Some extraction tools create two similarly named nested folders. The actual app folder is the inner one containing `README.md` and `.app`. Open that folder before running the commands below.

Move the extracted folder to a writable location that you will keep. For example:

```text
C:\Users\<your-user-name>\Documents\mojiokosi-simple
```

Important:

- Avoid protected locations such as `Program Files`
- Do not move or rename the folder after creating the desktop shortcut
- If you use a cloud-synced folder, verify that your provider actually completes synchronization
- The app itself does not provide cloud backup

The desktop shortcut stores an **absolute path** to the script. If you later move or rename the folder, rerun setup from the new location.

### 3. Run setup

Open the actual app folder identified above—the inner folder containing `README.md` and `.app`—in File Explorer.

An easy way to open PowerShell in that folder:

1. Click the address bar at the top of File Explorer
2. Type `powershell` and press Enter
3. Paste the following command into the blue or black window and press Enter

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

You can also use **Open in Terminal** in Windows 11 and run the command in PowerShell from the project folder.

Setup:

- Creates one desktop shortcut named `文字起こし`
- Creates the `transcripts` storage folder if needed
- Removes obsolete start/stop shortcuts from older versions of this app

The app is not copied to another installation directory. The extracted folder is the application itself. Deleting it will break the shortcut.

`-ExecutionPolicy Bypass` applies only to that PowerShell process. It does not permanently change the execution policy for the whole PC.

### 4. First launch and Windows setup

1. Double-click `文字起こし` on the desktop
2. If Windows shows Live Captions setup, follow its instructions
3. Download the speech-recognition files for the language you need
4. Play a short video and confirm that text appears
5. Close the app with the `×` button
6. Confirm that a new `.txt` file exists under `transcripts`

The initial language-file download requires an internet connection.

## Everyday use

1. Open `文字起こし` from the desktop
2. Play audio from a video, meeting, stream, or another app
3. Recognized text appears automatically
4. When finished, close it with `×`, `Esc`, or `Alt + F4`

The app starts a fresh Live Captions session. If you already opened Live Captions manually, it may be closed and restarted when this app launches.

Only one transcription window can run at a time. Opening the shortcut again while one is already running does not create a second window.

## Window controls

| Goal | Action |
| --- | --- |
| Move the window | Drag the empty top or outer margin |
| Resize freely | Drag any edge or corner |
| Snap to a half or continue to another monitor | Drag the top margin to the left or right edge, or press `Win + Left / Right`. Repeating the same direction continues from the outer edge onto the adjacent monitor |
| Move directly to another monitor and preserve the layout as closely as possible | Press `Win + Shift + Left / Right`. If the displays have different orientations, the layout is adapted to the movement direction and destination |
| Snap to a quarter | Drag the top margin to a screen corner, or press `Win + Up / Down` after snapping left or right. On a portrait monitor, this becomes a full-width top or bottom half so the text area is not too narrow |
| Maximize | Drag the top margin to the top-center edge, or press `Win + Up` |
| Restore the previous size | Drag the top margin from a snapped window toward the center. With the keyboard, press `Win + Down` once from maximized mode, or repeat it as needed from a half or quarter position |
| Enter or leave full screen | Press `F11` or double-click the top margin |
| Minimize | Press `Win + Down` while the window is at its normal size |
| Read older text | Use the mouse wheel, scrollbar, or keyboard |
| Copy text | Select text and press `Ctrl + C` |
| Exit | Click `×`, press `Esc`, or press `Alt + F4` |

`Win + Arrow` works while the transcription window is focused. Either the left or right Windows key can be used. Monitors are selected from their actual Windows coordinates, so layouts with vertically offset or different-resolution displays are supported. At an outer edge with no adjacent monitor, the window stays on that edge.

On a landscape monitor, the four corners produce quarter-screen layouts. On a portrait monitor, dragging to a corner or pressing `Win + Up / Down` from a left/right half produces a full-width top or bottom half, avoiding an excessively narrow text column. Left and right halves remain available. If high display scaling makes a screen too narrow to preserve the minimum window size in a split, the app automatically falls back to a layout that stays on-screen.

When you are at the bottom, the view follows new text automatically. While you are reading older lines or selecting text, the app tries to preserve the scroll position and selection.

The app keeps one display-only line of space below the newest text so the bottom line remains fully visible. This space is not written to the saved transcript file.

The window is not always-on-top. Click another app or use `Alt + Tab` to place a browser or another window in front of it. Multiple monitors are supported.

## Saved files

Each launch creates a new text file in the project’s `transcripts` folder.

```text
mojiokosi-simple\
├─ .app\
├─ transcripts\
│  ├─ caption-20260720-090000-123.txt
│  └─ caption-20260720-101530-456.txt
├─ .gitignore
└─ README.md
```

Filename format:

```text
caption-YYYYMMDD-HHMMSS-milliseconds.txt
```

Storage behavior:

- UTF-8 text encoding
- Timestamp uses the PC’s local time at launch
- One file per launch
- The same file is updated continuously during recognition
- The latest content is written again during a normal exit
- A file may be empty if no speech was recognized
- Old files are never deleted automatically
- Audio is not saved; only text is stored

Each save rewrites the complete file. If power or the drive fails during that write, the whole file—not only the final words—may be incomplete. After important sessions, verify the file and copy it to separate storage promptly.

## Essential backup

`transcripts` is listed in `.gitignore` and is excluded from ordinary Git commits, so it is not stored on GitHub during normal use. This protects private meeting and media content from accidental publication, but it cannot prevent an advanced user from force-adding the files.

Recommended backup procedure:

1. Close the transcription window with `×`
2. Copy the entire `transcripts` folder
3. Store it on another physical drive, external SSD/USB drive, NAS, or trusted cloud service
4. Open a file from the backup to verify that it is usable
5. Repeat regularly

A second folder on the same PC can be lost together with that PC or drive. Keep at least one copy on another device or a trusted online storage service.

Transcripts may contain personal or confidential information. You are responsible for access permissions, sharing settings, and encryption at the backup destination.

## Recovery after PC failure or replacement

### If you have a transcript backup

1. Update the new PC with Windows Update
2. Follow “Fast setup on a new PC” above and download the latest copy from GitHub
3. Fully extract it to a permanent location
4. Copy your backed-up `transcripts` folder into the new project root
5. Run `Install-Shortcuts.ps1` from the new location
6. Open `文字起こし` from the desktop
7. Download the language files again if Windows requests them
8. Test with a short audio clip and confirm that a new file is saved
9. Confirm that your older transcript files also open correctly

### If you do not have a transcript backup

The app can be downloaded again from GitHub, but old `transcripts` files do not exist in this repository. They cannot be restored from GitHub; recovery would require access to the old drive or a separate backup.

## Updating or moving the folder

Safest update procedure:

1. Exit the app
2. Back up `transcripts` from the old folder
3. Download a new ZIP from GitHub
4. Fully extract it to a separate permanent folder
5. Copy your backed-up `transcripts` into the new project root
6. Run the setup command from the new folder
7. Launch from the desktop shortcut and verify that a new transcript is saved
8. Delete the old folder only after everything is confirmed

If you only moved or renamed the folder, rerun this command from its new location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

Setup recreates the desktop shortcut with the new absolute path.

## Troubleshooting

### Nothing happens when the shortcut is opened

- Check the taskbar and `Alt + Tab` for an already-running transcription window
- Check whether the project folder was moved or renamed
- If it moved, rerun the setup command from the new location
- Keep the project in a writable folder, not `Program Files` or read-only storage

A manual launch may show an error in PowerShell:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\.app\Start-LiveCaptionsToNotepad.ps1
```

### Test Windows Live Captions by itself

Press `Win + Ctrl + L` and check whether the standard Windows Live Captions window starts.

- If it does not start, check Windows Update, Live Captions availability, and Windows settings
- If initial setup appears, follow it and download the language files
- If the standard Live Captions window also recognizes nothing, check Windows audio output, language, and recognition conditions

### `Windows ライブ キャプションを開始できません` (“Windows Live Captions could not be started”)

Check that the standard feature opens with `Win + Ctrl + L`, restart the PC, and try again. Also confirm that Windows 11 is version 22H2 or later and fully updated.

### `Windows ライブ キャプションの初期設定を完了してください` (“Complete the initial Windows Live Captions setup”)

Follow the Windows instructions and install speech-recognition files for the language you use. When setup is complete, close the window once and reopen `文字起こし`.

### The window opens but no text appears

- Confirm that audio is actually playing from the PC
- Check the Windows default output device
- For Bluetooth headsets or HDMI monitors, confirm that the intended device is the default output
- Match the Live Captions recognition language to the spoken language
- Test whether standard Live Captions recognizes the same audio with `Win + Ctrl + L`
- Check volume, speech clarity, background noise, and PC load

Windows Live Captions controls the audio source. Its microphone normally starts off, but this app does not technically lock or prohibit microphone input. If microphone captioning is enabled in Windows, microphone audio may also be recognized.

### Text is delayed, incorrect, duplicated, or missing

The app continuously reads a changing Live Captions display and makes a best effort to merge revisions and duplicates. Delay, errors, duplicated fragments, or missing text can still occur when:

- Background noise or music is loud
- Multiple people speak at once
- Audio is quiet, interrupted, or heavily compressed
- CPU or memory load is high
- A Windows update changes the Live Captions interface

Song lyrics, music, applause, and other non-speech events are not guaranteed to transcribe accurately.

### The window goes behind the browser

This is expected. The window is intentionally not always-on-top. Use `Alt + Tab` or the taskbar to bring it back.

### The window is missing or off-screen

- Select the transcription app with `Alt + Tab` and press `Win + Up`
- Restore the previous multi-monitor connection if one was disconnected
- Exit and relaunch the app

### No transcript file is created

- Confirm that the project folder is writable
- Do not run it from protected or read-only storage
- Check security-software history
- Use the manual launch command above to view errors

### PowerShell reports that script execution is blocked

If Windows marked the downloaded scripts as blocked, run the following from the project folder and then retry setup:

```powershell
Unblock-File .\.app\Install-Shortcuts.ps1
Unblock-File .\.app\Start-LiveCaptionsToNotepad.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.app\Install-Shortcuts.ps1
```

Do not unblock scripts from an untrusted source. Verify this repository URL and where your download came from first.

## Changing the output folder manually (advanced)

When launching without the desktop shortcut, use `-OutputDirectory` to select another destination:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\.app\Start-LiveCaptionsToNotepad.ps1 -OutputDirectory "D:\Transcripts"
```

The destination is created automatically when possible. This option applies only to that manual launch. The standard desktop shortcut continues to use `transcripts` under the project folder.

## Uninstalling

There is no dedicated uninstaller. Remove the app in this order:

1. Close the transcription window
2. Back up any needed `transcripts` files elsewhere
3. Delete the desktop shortcut named `文字起こし`
4. Delete the extracted app folder containing `README.md` and `.app`

The app does not install a service, startup item, scheduled task, or dedicated registry setting. Language files managed by Windows Live Captions are not removed by these steps.

> [!CAUTION]
> Deleting the project folder also deletes the `transcripts` folder inside it. Verify your backup first.

## Privacy and security

- Recognition is performed by Windows Live Captions
- Initial setup downloads language files from Microsoft
- Microsoft states that recognition runs on-device after those files are installed
- This app does not save an audio recording
- The scripts do not send audio or text to an external API
- Transcripts are stored as ordinary, unencrypted text files
- `transcripts` is excluded from GitHub, but files may still be visible to the OS, sync software, backup software, or other users with access

For confidential meetings, personal data, or important medical, legal, or financial content, follow your organization’s rules and retention policy and verify the text against the original audio or an official record.

## Limitations

- Accuracy cannot exceed what Windows Live Captions provides
- This is not a guarantee of a verbatim or legally authoritative record
- Recognition errors, omissions, duplicates, and punctuation differences may occur
- If Windows Update changes the Live Captions interface, text retrieval may stop working
- Launching the app may close and restart a Live Captions window that was opened manually
- The app does not automatically organize, delete, or cloud-sync old transcripts
- There is no automatic app updater

## Repository layout

```text
mojiokosi-simple\
├─ .app\
│  ├─ Install-Shortcuts.ps1
│  └─ Start-LiveCaptionsToNotepad.ps1
├─ transcripts\                 # Created locally during setup or first launch
├─ .gitignore
└─ README.md
```

- `Install-Shortcuts.ps1` creates the desktop shortcut
- `Start-LiveCaptionsToNotepad.ps1` starts Live Captions, reads text, displays it, and saves it
- `transcripts` stores personal transcript files and is excluded from GitHub

## Getting help

Use [GitHub Issues](https://github.com/tghcgu/mojiokosi-simple/issues) to report a problem. Include only information that is safe to publish:

- Windows 11 version
- Recognition language
- The action that triggered the problem
- The exact error message
- Whether standard Live Captions works with `Win + Ctrl + L`

Do not paste private transcripts or confidential information into a public issue.
