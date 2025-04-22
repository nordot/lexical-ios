/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MobileCoreServices
import UIKit

protocol LexicalTextViewDelegate: NSObjectProtocol {
    func textViewDidBeginEditing(textView: TextView)
    func textViewDidEndEditing(textView: TextView)
    func textViewShouldChangeText(_ textView: UITextView, range: NSRange, replacementText text: String) -> Bool
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
}

/// Lexical's subclass of UITextView. Note that using this can be dangerous, if you make changes that Lexical does not expect.
@objc public class TextView: UITextView {
    let editor: Editor

    let pasteboard = UIPasteboard.general
    let pasteboardIdentifier = "x-lexical-nodes"
    var isUpdatingNativeSelection = false
    var isShowTitlePlaceholder = false
    var layoutManagerDelegate: LayoutManagerDelegate

    // This is to work around a UIKit issue where, in situations like autocomplete, UIKit changes our selection via
    // private methods, and the first time we find out is when our delegate method is called. @amyworrall
    var interceptNextSelectionChangeAndReplaceWithRange: NSRange?
    weak var lexicalDelegate: LexicalTextViewDelegate?
    private var placeholderLabel: UILabel
    private var titleLabel: UILabel

    private let useInputDelegateProxy: Bool
    private let inputDelegateProxy: InputDelegateProxy

    fileprivate var textViewDelegate: TextViewDelegate = .init()

    // MARK: - Init

    init(editorConfig: EditorConfig, featureFlags: FeatureFlags) {
        let textStorage = TextStorage()
        let layoutManager = LayoutManager()
        layoutManagerDelegate = LayoutManagerDelegate()
        layoutManager.delegate = layoutManagerDelegate

        let textContainer = TextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        var reconcilerSanityCheck = featureFlags.reconcilerSanityCheck

        #if targetEnvironment(simulator)
        reconcilerSanityCheck = false
        #endif

        editor = Editor(
            featureFlags: FeatureFlags(reconcilerSanityCheck: reconcilerSanityCheck),
            editorConfig: editorConfig
        )
        textStorage.editor = editor
        placeholderLabel = UILabel(frame: .zero)
        titleLabel = UILabel(frame: .zero)

        useInputDelegateProxy = featureFlags.proxyTextViewInputDelegate
        inputDelegateProxy = InputDelegateProxy()

        super.init(frame: .zero, textContainer: textContainer)

        if useInputDelegateProxy {
            inputDelegateProxy.targetInputDelegate = inputDelegate
            super.inputDelegate = inputDelegateProxy
        }

        delegate = textViewDelegate
        textContainerInset = UIEdgeInsets(top: 8.0, left: 5.0, bottom: 8.0, right: 5.0)

        setUpPlaceholderLabel()
        setUpTitleLabel()

        registerRichText(editor: editor)
    }

    /// This init method is used for unit tests
    convenience init() {
        self.init(
            editorConfig: EditorConfig(
                theme: Theme(),
                plugins: [],
                isShowTitlePlaceHolder: true
            ),
            featureFlags: FeatureFlags()
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("\(#function) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        if isShowTitlePlaceholder {
            titleLabel.frame.origin = CGPoint(
                x: textContainer.lineFragmentPadding * 1.5 + textContainerInset.left,
                y: textContainerInset.top
            )
            titleLabel.sizeToFit()

            if let height = firstLineHeight() {
                placeholderLabel.frame.origin = CGPoint(x: textContainer.lineFragmentPadding * 1.5 + textContainerInset.left, y: height + textContainerInset.top)
                placeholderLabel.sizeToFit()
            }
        } else {
            placeholderLabel.frame.origin = CGPoint(x: textContainer.lineFragmentPadding * 1.5 + textContainerInset.left, y: textContainerInset.top)
            placeholderLabel.sizeToFit()
        }
    }

    override public func caretRect(for position: UITextPosition) -> CGRect {
        var caretRect = super.caretRect(for: position)
        let characterIndex = offset(from: beginningOfDocument, to: position)

        guard layoutManager.isValidGlyphIndex(characterIndex) else {
            return caretRect
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let usedLineFragment = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        guard !usedLineFragment.isEmpty else {
            return caretRect
        }

        caretRect.origin.y = usedLineFragment.origin.y + textContainerInset.top
        caretRect.size.height = usedLineFragment.size.height

        return caretRect
    }

    override public var inputDelegate: UITextInputDelegate? {
        get {
            if useInputDelegateProxy {
                return inputDelegateProxy.targetInputDelegate
            } else {
                return super.inputDelegate
            }
        }
        set {
            if useInputDelegateProxy {
                inputDelegateProxy.targetInputDelegate = newValue
            } else {
                super.inputDelegate = newValue
            }
        }
    }

    // MARK: - Incoming events

    override public func deleteBackward() {
        editor.log(.UITextView, .verbose, "deleteBackward()")

        let previousSelectedRange = selectedRange

        inputDelegateProxy.isSuspended = true // do not send selection changes during deleteBackwards, to not confuse third party keyboards
        defer {
            inputDelegateProxy.isSuspended = false
        }

        editor.dispatchCommand(type: .deleteCharacter, payload: true)

        if previousSelectedRange.length > 0 {
            // Expect new selection to be on the start of selection
            if selectedRange.location != previousSelectedRange.location || selectedRange.length != 0 {
                inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
            }
        } else {
            // Expect new selection to be somewhere before selection -- we could calculate this by considering
            // unicode characters, but it would be complex. Let's do a best effort, since this situation is rare anyway.
            if selectedRange.length != 0 || selectedRange.location >= previousSelectedRange.location {
                inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
            }
        }
    }

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            if pasteboard.hasStrings {
                return true
            } else if !(pasteboard.data(forPasteboardType: LexicalConstants.pasteboardIdentifier)?.isEmpty ?? true) {
                return true
            } else if !(pasteboard.data(forPasteboardType: kUTTypeUTF8PlainText as String)?.isEmpty ?? true) {
                return true
            } else {
                return super.canPerformAction(action, withSender: sender)
            }
        } else if action == #selector(selectAll) {
            return true
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }

    func codeBlockRange(at location: Int) -> NSRange? {
        let fullRange = NSRange(location: 0, length: self.attributedText.length)
        var effectiveRange = NSRange()
        let attr = attributedText.attribute(.codeBlockCustomDrawing, at: location, longestEffectiveRange: &effectiveRange, in: fullRange)

        if let _ = attr as? Lexical.CodeBlockCustomDrawingAttributes {
            let endLocation = NSMaxRange(effectiveRange)
            if endLocation <= attributedText.length,
               attributedText.attributedSubstring(from: NSRange(location: endLocation - 1, length: 1)).string == "\n" {
                effectiveRange.length -= 1
            }

            return effectiveRange
        }

        return nil
    }

    func quoteBlockRange(at location: Int) -> NSRange? {
        let fullRange = NSRange(location: 0, length: self.attributedText.length)
        var effectiveRange = NSRange()
        let attr = attributedText.attribute(
            .quoteCustomDrawing,
            at: location,
            longestEffectiveRange: &effectiveRange,
            in: fullRange
        )

        if let _ = attr as? Lexical.QuoteCustomDrawingAttributes {
            let endLocation = NSMaxRange(effectiveRange)
            if endLocation <= attributedText.length,
               attributedText.attributedSubstring(from: NSRange(location: endLocation - 1, length: 1)).string == "\n" {
                effectiveRange.length -= 1
            }

            return effectiveRange
        }

        return nil
    }

    override public func selectAll(_ sender: Any?) {
        guard let text = text, let selectedTextRange = selectedTextRange else { return }
        let nsText = text as NSString
        let cursorPosition = offset(from: beginningOfDocument, to: selectedTextRange.start)

        if let codeRange = codeBlockRange(at: selectedRange.location) {
            self.selectedRange = codeRange
            return
        }

        if let quoteRange = quoteBlockRange(at: selectedRange.location) {
            self.selectedRange = quoteRange
            return
        }

        // Get the range of the first line (title line)
        let firstLineRange = nsText.lineRange(for: NSRange(location: 0, length: 0))

        // Get the range of the last line (to exclude it)
        let lastLineRange = nsText.lineRange(for: NSRange(location: nsText.length - 1, length: 0))

        // Start of body (line 2)
        var secondLineStart = NSMaxRange(firstLineRange)
        let secondLastLineEnd = lastLineRange.location - 1
        if !isShowTitlePlaceholder {
            secondLineStart = firstLineRange.location
        }

        var bodyRange = NSRange(location: secondLineStart, length: max(secondLastLineEnd - secondLineStart + 1, 0))

        // Remove trailing newline if exists
        if secondLastLineEnd >= 0, nsText.character(at: secondLastLineEnd) == 10 {
            bodyRange.length -= 1
        }

        DispatchQueue.main.async {
            self.selectedTextRange = nil

            if cursorPosition < firstLineRange.upperBound && self.isShowTitlePlaceholder {
                // Select title
                var length = firstLineRange.length
                if length > 0, nsText.character(at: firstLineRange.location + length - 1) == 10 {
                    length -= 1
                }
                self.selectedRange = NSRange(location: firstLineRange.location, length: length)
            } else {
                // Select body (excluding last line)
                self.selectedRange = bodyRange
            }
        }
    }

    override public func copy(_ sender: Any?) {
        editor.dispatchCommand(type: .copy, payload: pasteboard)
    }

    override public func cut(_ sender: Any?) {
        editor.dispatchCommand(type: .cut, payload: pasteboard)
    }

    override public func paste(_ sender: Any?) {
        editor.dispatchCommand(type: .paste, payload: pasteboard)
    }

    override public func insertText(_ text: String) {
        editor.log(.UITextView, .verbose, "Text view selected range \(String(describing: selectedRange))")

        let expectedSelectionLocation = selectedRange.location + text.lengthAsNSString()

        inputDelegateProxy.isSuspended = true // do not send selection changes during insertText, to not confuse third party keyboards
        defer {
            inputDelegateProxy.isSuspended = false
        }

        guard let textStorage = textStorage as? TextStorage else {
            // This should never happen, we will always have a custom text storage.
            editor.log(.TextView, .error, "Missing custom text storage")
            return
        }

        textStorage.mode = TextStorageEditingMode.controllerMode
        editor.dispatchCommand(type: .insertText, payload: text)
        textStorage.mode = TextStorageEditingMode.none

        // check if we need to send a selectionChanged (i.e. something unexpected happened)
        if selectedRange.length != 0 || selectedRange.location != expectedSelectionLocation {
            inputDelegateProxy.sendSelectionChangedIgnoringSuspended(self)
        }
    }

    // MARK: Marked text

    override public func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
        editor.log(.UITextView, .verbose)
        if let markedText {
            setMarkedTextInternal(markedText.string, selectedRange: selectedRange)
        } else {
            unmarkText()
        }
    }

    override public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        editor.log(.UITextView, .verbose)
        if let markedText {
            setMarkedTextInternal(markedText, selectedRange: selectedRange)
        } else {
            unmarkText()
        }
    }

    private func setMarkedTextInternal(_ markedText: String, selectedRange: NSRange) {
        editor.log(.TextView, .verbose)
        guard let textStorage = textStorage as? TextStorage else {
            // This should never happen, we will always have a custom text storage.
            editor.log(.TextView, .error, "Missing custom text storage")
            super.setMarkedText(markedText, selectedRange: selectedRange)
            return
        }

        if markedText.isEmpty, let markedRange = editor.getNativeSelection().markedRange {
            textStorage.replaceCharacters(in: markedRange, with: "")
            return
        }

        let markedTextOperation = MarkedTextOperation(createMarkedText: true,
                                                      selectionRangeToReplace: editor.getNativeSelection().markedRange ?? self.selectedRange,
                                                      markedTextString: markedText,
                                                      markedTextInternalSelection: selectedRange)

        let behaviourModificationMode = UpdateBehaviourModificationMode(suppressReconcilingSelection: true, suppressSanityCheck: true, markedTextOperation: markedTextOperation)

        textStorage.mode = TextStorageEditingMode.controllerMode
        defer {
            textStorage.mode = TextStorageEditingMode.none
        }
        do {
            // set composition key
            try editor.read {
                guard let selection = try getSelection() as? RangeSelection else {
                    editor.log(.TextView, .error, "Could not get selection in setMarkedTextInternal()")
                    throw LexicalError.invariantViolation("should have selection when starting marked text")
                }

                editor.compositionKey = selection.anchor.key
            }

            // insert text
            try onInsertTextFromUITextView(text: markedText, editor: editor, updateMode: behaviourModificationMode)
        } catch {
            let language = textInputMode?.primaryLanguage
            editor.log(.TextView, .error, "exception thrown, lang \(String(describing: language)): \(String(describing: error))")
            unmarkTextWithoutUpdate()
            return
        }
    }

    func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
        editor.log(.TextView, .verbose)
        isUpdatingNativeSelection = true
        super.setAttributedMarkedText(markedText, selectedRange: selectedRange)
        interceptNextSelectionChangeAndReplaceWithRange = nil
        onSelectionChange(editor: editor)
        isUpdatingNativeSelection = false
        editor.compositionKey = nil
        showPlaceholderText()
    }

    override public func unmarkText() {
        editor.log(.UITextView, .verbose)
        let previousMarkedRange = editor.getNativeSelection().markedRange
        let oldIsUpdatingNative = isUpdatingNativeSelection
        isUpdatingNativeSelection = true
        super.unmarkText()
        isUpdatingNativeSelection = oldIsUpdatingNative
        if let previousMarkedRange {
            // find all nodes in selection. Mark dirty. Reconcile. This should correct all the attributes to be what we expect.
            do {
                try editor.update {
                    guard let anchor = try pointAtStringLocation(previousMarkedRange.location, searchDirection: .forward, rangeCache: editor.rangeCache),
                          let focus = try pointAtStringLocation(previousMarkedRange.location + previousMarkedRange.length, searchDirection: .forward, rangeCache: editor.rangeCache)
                    else {
                        return
                    }

                    let markedRangeSelection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
                    _ = try markedRangeSelection.getNodes().map { node in
                        internallyMarkNodeAsDirty(node: node, cause: .userInitiated)
                    }

                    editor.compositionKey = nil
                }
            } catch {}
        }
    }

    func unmarkTextWithoutUpdate() {
        editor.log(.TextView, .verbose)
        super.unmarkText()
    }

    // MARK: - Lexical internal

    func presentDeveloperFacingError(message: String) {
        let alert = UIAlertController(title: "Lexical Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
        if let rootViewController = window?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }

    func updateNativeSelection(from selection: RangeSelection) throws {
        isUpdatingNativeSelection = true
        defer { isUpdatingNativeSelection = false }
        let nativeSelection = try createNativeSelection(from: selection, editor: editor)

        if let range = nativeSelection.range {
            selectedRange = range
        }
    }

    func resetSelectedRange() {
        selectedRange = NSRange(location: 0, length: 0)
    }

    func defaultClearEditor() throws {
        editor.resetEditor(pendingEditorState: nil)
        editor.dispatchCommand(type: .clearEditor)
    }

    func setPlaceholderText(_ text: String, textColor: UIColor, font: UIFont) {
        placeholderLabel.text = text
        placeholderLabel.textColor = textColor
        placeholderLabel.font = font
        self.font = font
    }

    func setTitlePlaceholderText(_ text: String, textColor: UIColor, font: UIFont) {
        titleLabel.text = text
        titleLabel.textColor = textColor
        titleLabel.font = font
        self.font = font
    }

    func showPlaceholderText() {
        do {
            var shouldShowTitlePlaceHolder = false
            var shouldShowBodyPlaceHolder = false

            try editor.read {
                guard let root = getRoot() else { return }

                shouldShowTitlePlaceHolder = root.getTitleTextContent()
                    .replacingOccurrences(of: "\n", with: "")
                    .isEmpty

                shouldShowBodyPlaceHolder = root.getBodyTextContent()
                    .replacingOccurrences(of: "\n", with: "")
                    .isEmpty
            }

            if !shouldShowTitlePlaceHolder { hideTitleLabel() }
            if !shouldShowBodyPlaceHolder { hidePlaceholderLabel() }

            guard shouldShowTitlePlaceHolder || shouldShowBodyPlaceHolder else { return }

            try editor.read {
                titleLabel.isHidden = !canShowTitlePlaceholder(isComposing: editor.isComposing())
                placeholderLabel.isHidden = !canShowBodyPlaceholder(isComposing: editor.isComposing())

                layoutIfNeeded()
            }
        } catch {}
    }

    // MARK: - Private

    private func setUpPlaceholderLabel() {
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.isHidden = true
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.numberOfLines = 1
        addSubview(placeholderLabel)
    }

    private func setUpTitleLabel() {
        titleLabel.backgroundColor = .clear
        titleLabel.isHidden = true
        titleLabel.isAccessibilityElement = false
        titleLabel.numberOfLines = 1
        addSubview(titleLabel)
    }

    fileprivate func hidePlaceholderLabel() {
        placeholderLabel.isHidden = true
    }

    fileprivate func hideTitleLabel() {
        titleLabel.isHidden = true
    }

    override public func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if r == true {
            onSelectionChange(editor: editor)
        }
        return r
    }

    func firstLineHeight() -> CGFloat? {
        guard let text = text, !text.isEmpty else { return nil }
        let nsText = text as NSString
        let firstLineRange = nsText.lineRange(for: NSMakeRange(0, 0))
        let layoutManager = self.layoutManager

        var glyphRange = NSRange()
        layoutManager.characterRange(forGlyphRange: firstLineRange, actualGlyphRange: &glyphRange)

        var totalHeight: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            totalHeight += rect.height
        }

        return totalHeight
    }
}

private class TextViewDelegate: NSObject, UITextViewDelegate {
    public func textViewDidChangeSelection(_ textView: UITextView) {
        // Ensure the UITextView is our custom TextView subclass
        guard let textView = textView as? TextView else { return }
        guard let range = textView.selectedTextRange else { return }
        guard let nsText = textView.text as NSString? else { return }

        // Convert UITextRange to NSRange
        let selectionStart = textView.offset(from: textView.beginningOfDocument, to: range.start)
        let selectionEnd = textView.offset(from: textView.beginningOfDocument, to: range.end)

        // Get range of the first line (title line)
        let firstLineRange = nsText.lineRange(for: NSRange(location: 0, length: 0))

        // Get range of the last line (used to block access to it)
        let lastLineRange = nsText.lineRange(for: NSRange(location: max(nsText.length - 1, 0), length: 0))

        // The start of body (second line)
        let secondLineStart = firstLineRange.upperBound

        // The position before last line starts (to exclude it)
        let beforeLastLineEnd = lastLineRange.location

        // Initialize adjusted selection range
        var validStart = selectionStart
        var validEnd = selectionEnd

        if selectionStart < firstLineRange.length && textView.isShowTitlePlaceholder {
            // If selection starts in the first line, limit it to only the first line
            validStart = max(validStart, firstLineRange.location)
            validEnd = min(validEnd, firstLineRange.upperBound - 1) // exclude line break
        } else {
            if !textView.isShowTitlePlaceholder {
                validStart = max(validStart, firstLineRange.location)
                validEnd = min(validEnd, beforeLastLineEnd - 1) // exclude line break before last line
            } else {
                // If selection starts in the body, restrict to second line up to before last line
                validStart = max(validStart, secondLineStart)
                validEnd = min(validEnd, beforeLastLineEnd - 1) // exclude line break before last line
            }
        }

        // Apply the corrected range if any change is detected
        if validStart != selectionStart || validEnd != selectionEnd,
           let newStart = textView.position(from: textView.beginningOfDocument, offset: validStart),
           let newEnd = textView.position(from: textView.beginningOfDocument, offset: validEnd),
           let newRange = textView.textRange(from: newStart, to: newEnd)
        {
            textView.isUpdatingNativeSelection = true
            defer { textView.isUpdatingNativeSelection = false }
            textView.selectedTextRange = newRange
            onSelectionChange(editor: textView.editor, isLastLine: true)
            return
        }

        // Skip native update if we're in the middle of programmatic changes
        if textView.isUpdatingNativeSelection { return }

        // Handle intercepted selection range replacement if needed
        if let interception = textView.interceptNextSelectionChangeAndReplaceWithRange {
            textView.interceptNextSelectionChangeAndReplaceWithRange = nil
            textView.selectedRange = interception
            return
        }

        // Trigger lexical editor selection sync
        onSelectionChange(editor: textView.editor)
    }

    private func isCursorAtLastLine(textView: UITextView, cursorPosition: Int) -> Bool {
        guard let text = textView.text, !text.isEmpty else { return false }
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let glyphIndex = layoutManager.characterIndex(for: textView.caretRect(for: textView.selectedTextRange!.start).origin,
                                                      in: textContainer,
                                                      fractionOfDistanceBetweenInsertionPoints: nil)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

        let lastGlyphIndex = layoutManager.numberOfGlyphs - 1
        var lastLineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: &lastLineRange)

        return lineRange.location == lastLineRange.location
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let textView = textView as? TextView else { return false }

        if let lexicalDelegate = textView.lexicalDelegate {
            return lexicalDelegate.textViewShouldChangeText(textView, range: range, replacementText: text)
        }

        return true
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        guard let textView = textView as? TextView else { return }
        textView.lexicalDelegate?.textViewDidBeginEditing(textView: textView)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        guard let textView = textView as? TextView else { return }
        textView.lexicalDelegate?.textViewDidEndEditing(textView: textView)
    }

    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard let textView = textView as? TextView else { return false }

        let nativeSelection = NativeSelection(range: characterRange, affinity: .backward)
        try? textView.editor.update {
            guard let selection = try getSelection() as? RangeSelection else {
                // TODO: cope with non range selections. Should just make a range selection here
                return
            }
            try selection.applyNativeSelection(nativeSelection)
        }
        let handledByLexical = textView.editor.dispatchCommand(type: .linkTapped, payload: URL)

        if handledByLexical {
            return false
        }

        if !textView.isEditable {
            return true
        }

        return textView.lexicalDelegate?.textView(textView, shouldInteractWith: URL, in: characterRange, interaction: interaction) ?? false
    }
}
