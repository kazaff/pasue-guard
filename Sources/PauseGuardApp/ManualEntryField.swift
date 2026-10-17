import AppKit
import SwiftUI

/// A normal field editor with clipboard import disabled; IME input stays native.
@MainActor final class ManualEntryEditor: NSTextView {
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [] }
    override func readSelection(from pboard: NSPasteboard) -> Bool { false }
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { false }
    override func paste(_ sender: Any?) {}
    override func pasteAsPlainText(_ sender: Any?) {}
    override func pasteAsRichText(_ sender: Any?) {}
}

@MainActor final class ManualEntryCell: NSTextFieldCell {
    private let editor: ManualEntryEditor = {
        let editor = ManualEntryEditor()
        editor.isFieldEditor = true
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        return editor
    }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

struct ManualEntryField: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.cell = ManualEntryCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "手动输入上方咒骂语"
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel("手动输入显示的咒骂语")
        field.setAccessibilityHelp("不支持粘贴。含标点和空格完全一致，且等待结束后可以确认解除。")
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        // Avoid replacing marked text while a Chinese IME composition is active.
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
