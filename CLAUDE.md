## Code Best Practices

- インラインコードの制限: Swift内で1行を超えるJavaScript、HTML、CSSを記述しないでください。新しいファイルを作成し、既存のテンプレートメカニズム（iTermBrowserTemplateLoader.swiftなど）を使用してロードしてください。
- エラーハンドリング (Swift): fatalError や assert の代わりに it_fatalError および it_assert を使用してください。これらを使用しないと、有用なクラッシュログが生成されません。
- エラーハンドリング (ObjC): assert も使用可能ですが、ITAssertWithMessage がより好ましいです。
- 依存関係: 循環参照（Dependency Cycles）を作成しないでください。デリゲートやクロージャを使用して回避してください。
- 重複の排除: 重複する式を避け、分岐の前に共有の計算を const（定数）として抽出してください。
- デフォルト設定: デフォルトの設定を断りなく（サイレントに）変更しないでください。

- Auto Layout の禁止領域: ターミナルウィンドウ内では絶対に Auto Layout を使用しないでください。 自動リサイズ機能（autoresizing mask）を損なう原因になります。
- ※既存の自動リサイズコードがあまり含まれていない他のウィンドウ（AIチャットウィンドウなど）では Auto Layout を使用しても問題ありません。
- 展開ターゲット: デプロイターゲットは macOS 12 です。macOS 12以下のバージョンに対する可用性チェック（@availableなど）を追加する必要はありません。

- 引用符の厳守: カーリークォート（“”）をストレートクォート（""）に置き換えないでください。アポストロフィ（’’）も同様です。
- 参考：コピー用（ ‘’“” ）
ユーザー可視文字列: ユーザーに見える文字列では、インチ（inch）の略称として使用する場合を除き、" を使用しないでください。代わりにカーリークォート “ および ” を使用してください。


- 新規ファイル: 新しいファイルを作成したら、すぐに git add してください。
- Xcodeへの追加: ファイルをXcodeプロジェクトに追加する際は、スクリプトを使用してください：
 tools/add_file_to_xcodeproj.rb <file_path> <target_name>
 例：tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC

- リネーム: Gitで追跡されているファイルの名前を変更する場合は、mv ではなく git mv を使用してください。

- サブモジュール: 明示的な許可なくサブモジュールを git add しないでください。
- claude で生成したデータは、claudeディレクトリに保存