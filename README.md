# ROTO.com — PC-9801 Rotozoom

PC-98 用 MS-DOS の回転・拡大縮小デモです。640×400・8色、PEGCでは256色を
選択できます。内部描画160×100（4×4ドット単位）。ハイレゾ機では1120×750画面の
中央に640×400・8色で表示します。テクスチャを内蔵し、実行時の追加ファイルは不要です。

## 実行

PC-98 の通常解像度機種またはハイレゾ機／対応エミュレーターで DOS を起動し、`ROTO.com`
をコピーして実行します。Windows 上で直接実行するプログラムではありません。

```text
ROTO          二画面切替で連続実行（VM/VX/RA など）
ROTO /S       単一 VRAM 画面（初代 PC-9801 / U 向け）
ROTO /T       16フレーム描画して自動終了
ROTO /S /T    単一画面で自動終了
ROTO /256     PEGC 640×400・256色（単一画面）
ROTO /8       8色互換描画（既定）
ROTO /?       ヘルプ
```

**Esc または Q で終了**します。通常の DOS テキスト画面から起動してください。
8086 命令のみを使用。速度は CPU に依存します。ハイレゾモードはBIOSフラグで自動判定し、
単一画面で動作します。GRCG搭載機は全プレーン同時クリア、EGC搭載機はGRCG互換経路を
使用します（EGC専用ビットブロック転送は使用しません）。PEGCは通常の8色描画と
`/256`のパックトピクセル描画に対応します。非対応機の`/256`は画面変更前に終了コード1で拒否します。
ハイレゾ機の256色オプションボードや他社アクセラレーターは対象外です。
音源は自動判別し、26K/73/86 の FM+SSG で再生します。86 と判定できた場合だけ
PCM のキック、スネア、ハイハット、フィル、転調効果音を追加します。`/M` で無音化、
`/P` で約12.8秒の音楽プレビューです。
終了時はテキスト表示と VRAM ページ0へ戻ります。既存のグラフィック内容・パレットの
完全復元は行いません。音源のレジスターと PCM FIFO は停止・無音化してから終了します。

## ビルド・検証

Python 3 と NASM 2.16.03 を用意して PowerShell から実行します。
NASM は PATH または `tools/nasm-2.16.03/nasm.exe` に置きます。

```powershell
./build.ps1 -Python python -Nasm nasm
./build-asw.ps1 -Python python -AswRoot E:/aswcurr
python -m pip install unicorn==2.1.4 pillow
python tests/verify.py
python tests/verify_sound.py
python tests/verify_video.py
./tests/dosbox-smoke.ps1 -Dosbox 'E:/DOSBox-X/dosbox-x.exe'
./tests/dosbox-audio.ps1 -Dosbox 'E:/DOSBox-X/dosbox-x.exe' -Board board26k
./tests/dosbox-audio.ps1 -Dosbox 'E:/DOSBox-X/dosbox-x.exe' -Board board86
```

`build.ps1` はテーブル生成と flat binary のアセンブルを行います。
`build-asw.ps1` はASW版 `ROTOASW.com` を作成します。単独でアセンブル可能な
ASWソースは [src/asw/roto.asm](src/asw/roto.asm) です。NASM版ソースから
`src/make_asw.py`で生成し、画像・音源データもソース内へ展開しています。
ASWビルドにはNASMは不要です。両アセンブラーの命令符号化は一部異なるため、
バイナリの完全一致ではなく実行結果の一致を検証しています。
NASM の `reloc-abs-word` 診断のみ除外しています。これは `org 100h` の
16ビット絶対アドレスを警告するためで、COM のサイズ制限は別に検査します。
他の警告はエラーとして扱います。

実バイナリを Unicorn で実行し、各画素の参照計算との一致、VRAM 書込み範囲、
ページ切替、キー終了、VSYNC 固着時の有限時間終了、ヘルプを検証します。
結果は `build/verification.json`、描画例は `build/frame-*.png` に生成します。
このテストの BIOS/DOS はモデルであり、実機 ROM の代替検証ではありません。
`verify_video.py` は両COMについてGRCG/EGC互換描画、PEGC256色の全バンク境界、
256個のパレット、ハイレゾのプレーン選択・中央配置・テキスト領域保護とBIOS呼出を
検証します。実機、ハイレゾROMでの実行は未検証です。

音源テストは `build/audio-verification.json` に記録します。楽曲はオリジナルの
`bVI-bVII-i-i`（長調表記の IV-V-vi）を4小節単位で半音ずつ12キーへ連続転調します。
DOSBox-X の `DX-CAPTURE` はビルドによって WAV 出力が無効な場合があります。その場合も
26K/86 の実行・音源選択は検証し、PCM の内容・FIFO・停止処理は Unicorn で検証します。

ハードウェアの解析根拠・各モジュールの役割は
[docs/pc9801-analysis.md](docs/pc9801-analysis.md)、検証結果は
[docs/verification.md](docs/verification.md) を参照してください。
今回の追加機能と検証範囲は [docs/video-backends.md](docs/video-backends.md) と
[docs/verification-q003.md](docs/verification-q003.md) にまとめています。
指定された GNA 管理記録は `plan/` にあります。
