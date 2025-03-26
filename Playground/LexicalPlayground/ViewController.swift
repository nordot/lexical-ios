/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import EditorHistoryPlugin
import Lexical
import LexicalInlineImagePlugin
import LexicalLinkPlugin
import LexicalListPlugin
import UIKit

class ViewController: UIViewController, UIToolbarDelegate {
    var lexicalView: LexicalView?
    weak var toolbar: UIToolbar?
    weak var hierarchyView: UIView?
    private let editorStatePersistenceKey = "editorState"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let editorHistoryPlugin = EditorHistoryPlugin()
        let toolbarPlugin = ToolbarPlugin(viewControllerForPresentation: self, historyPlugin: editorHistoryPlugin)
        let toolbar = toolbarPlugin.toolbar
        toolbar.delegate = self

        let hierarchyPlugin = NodeHierarchyViewPlugin()
        let hierarchyView = hierarchyPlugin.hierarchyView
        let listPlugin = ListPlugin()
        let imagePlugin = InlineImagePlugin()
        let linkPlugin = LinkPlugin()

        let theme = Theme()
        theme.paragraph = [
            .fontSize: 16,
            .lineHeight: 24
        ]
        theme.title = [
            .fontSize: 24,
            .lineHeight: 24,
            .paragraphSpacingBefore: 8,
            .paragraphSpacing: 8
        ]
        theme.link = [
            .foregroundColor: UIColor.systemBlue
        ]
        theme.quote = [
            .paddingHead: 8,
            .paddingTail: -8,
            .fontSize: 16,
            .lineHeight: 24
        ]
        theme.setBlockLevelAttributes(
            .code,
            value: BlockLevelAttributes(
                marginTop: 0,
                marginBottom: 0,
                paddingTop: 8,
                paddingBottom: 8
            )
        )

        let editorConfig = EditorConfig(
            theme: theme,
            plugins: [
                toolbarPlugin,
                listPlugin,
                hierarchyPlugin,
                imagePlugin,
                linkPlugin,
                editorHistoryPlugin
            ],
            isShowTitlePlaceHolder: true
        )
        let lexicalView = LexicalView(
            editorConfig: editorConfig,
            featureFlags: FeatureFlags(),
            placeholderText: LexicalPlaceholderText(
                text: "Write",
                font: .systemFont(ofSize: 16),
                color: UIColor.placeholderText
            ),
            titlePlaceholderText: LexicalPlaceholderText(
                text: "Title",
                font: .systemFont(ofSize: 24),
                color: UIColor.placeholderText
            )
        )

        linkPlugin.lexicalView = lexicalView
        toolbarPlugin.lexicalView = lexicalView

        self.lexicalView = lexicalView
        self.toolbar = toolbar
        self.hierarchyView = hierarchyView

        restoreEditorState()

        view.addSubview(lexicalView)
        view.addSubview(toolbar)
        view.addSubview(hierarchyView)

        navigationItem.title = "Lexical"
        setUpExportMenu()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let lexicalView, let toolbar, let hierarchyView {
            let safeAreaInsets = view.safeAreaInsets
            let hierarchyViewHeight = 300.0

            toolbar.frame = CGRect(x: 0,
                                   y: safeAreaInsets.top,
                                   width: view.bounds.width,
                                   height: 44)
            lexicalView.frame = CGRect(x: 0,
                                       y: toolbar.frame.maxY,
                                       width: view.bounds.width,
                                       height: view.bounds.height - toolbar.frame.maxY - safeAreaInsets.bottom - hierarchyViewHeight)
            hierarchyView.frame = CGRect(x: 0,
                                         y: lexicalView.frame.maxY,
                                         width: view.bounds.width,
                                         height: hierarchyViewHeight)
        }
    }

    func persistEditorState() {
        guard let editor = lexicalView?.editor else {
            return
        }

        let currentEditorState = editor.getEditorState()

        // turn the editor state into stringified JSON
        guard let jsonString = try? currentEditorState.toJSON() else {
            return
        }

        UserDefaults.standard.set(jsonString, forKey: editorStatePersistenceKey)
    }

    func restoreEditorState() {
        guard let editor = lexicalView?.editor else {
            return
        }

        guard let jsonString = UserDefaults.standard.value(forKey: editorStatePersistenceKey) as? String else {
            return
        }

        // turn the JSON back into a new editor state
        guard let newEditorState = try? EditorState.fromJSON(json: jsonString, editor: editor) else {
            return
        }

        // install the new editor state into editor
        try? editor.setEditorState(newEditorState)
    }

    func setUpExportMenu() {
        let menuItems = [
            UIAction(title: "Export HTML", handler: { [weak self] _ in
                self?.showExportScreen(.html)
            }),
            UIAction(title: "Export JSON", handler: { [weak self] _ in
                self?.showExportScreen(.json)
            })
        ]
        let menu = UIMenu(title: "Export as…", children: menuItems)
        let barButtonItem = UIBarButtonItem(title: "Export", style: .plain, target: nil, action: nil)
        barButtonItem.menu = menu
        navigationItem.rightBarButtonItem = barButtonItem
    }

    func showExportScreen(_ type: OutputFormat) {
        guard let editor = lexicalView?.editor else { return }
        let vc = ExportOutputViewController(editor: editor, format: type)
        navigationController?.pushViewController(vc, animated: true)
    }

    func position(for bar: UIBarPositioning) -> UIBarPosition {
        return .top
    }
}
