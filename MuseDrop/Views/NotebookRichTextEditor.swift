//
//  NotebookRichTextEditor.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct NotebookRichTextEditor: NSViewRepresentable {
    @Binding var plainText: String
    @Binding var richContent: Data?
    @Binding var formatting: NotebookPageFormatting
    @Binding var formatCommand: NotebookFormatCommand?
    
    let lineSpacing: CGFloat
    let marginInset: CGFloat
    let topInset: CGFloat
    let usesFixedLineHeight: Bool
    var onContentChange: (String, Data?) -> Void = { _, _ in }
    var onSelectionChange: (String) -> Void = { _ in }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        let textView = NotebookTextView()
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: marginInset + 8, height: topInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.insertionPointColor = formatting.inkColor
        
        context.coordinator.loadContent(into: textView)
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        
        textView.textContainerInset = NSSize(width: marginInset + 8, height: topInset)
        textView.insertionPointColor = formatting.inkColor
        textView.typingAttributes = context.coordinator.baseTypingAttributes()
        
        if let command = formatCommand {
            context.coordinator.apply(command, to: textView)
            DispatchQueue.main.async {
                if self.formatCommand == command {
                    self.formatCommand = nil
                }
            }
        }
        
        if context.coordinator.lastFormatting != formatting {
            context.coordinator.lastFormatting = formatting
            textView.typingAttributes = context.coordinator.baseTypingAttributes()
            context.coordinator.applyDefaultStyle(to: textView)
        }
        
        if context.coordinator.lastRichContent != richContent,
           !context.coordinator.isUpdatingFromView {
            context.coordinator.lastRichContent = richContent
            context.coordinator.loadContent(into: textView)
        }
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotebookRichTextEditor
        weak var textView: NSTextView?
        var isUpdatingFromBinding = false
        var isUpdatingFromView = false
        var lastRichContent: Data?
        var lastFormatting: NotebookPageFormatting?

        init(parent: NotebookRichTextEditor) {
            self.parent = parent
            self.lastFormatting = parent.formatting
            self.lastRichContent = parent.richContent
        }
        
        func loadContent(into textView: NSTextView) {
            isUpdatingFromBinding = true
            if let data = parent.richContent,
               let attributed = NSAttributedString(rtf: data, documentAttributes: nil),
               attributed.length > 0 {
                textView.textStorage?.setAttributedString(attributed)
            } else if !parent.plainText.isEmpty {
                textView.string = parent.plainText
                applyDefaultStyle(to: textView)
            } else {
                textView.string = ""
                textView.typingAttributes = baseTypingAttributes()
            }
            isUpdatingFromBinding = false
        }
        
        func shouldReloadPlainText(_ plain: String) -> Bool {
            guard let textView else { return false }
            return !isUpdatingFromView && plain != textView.string && parent.richContent == nil
        }
        
        func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            if parent.usesFixedLineHeight {
                paragraph.minimumLineHeight = parent.lineSpacing
                paragraph.maximumLineHeight = parent.lineSpacing
                paragraph.lineSpacing = 0
            } else {
                paragraph.lineSpacing = 4
            }
            paragraph.paragraphSpacing = 0
            
            return [
                .font: parent.formatting.font,
                .foregroundColor: parent.formatting.inkColor,
                .paragraphStyle: paragraph
            ]
        }
        
        func applyDefaultStyle(to textView: NSTextView) {
            guard let storage = textView.textStorage, storage.length > 0 else {
                textView.typingAttributes = baseTypingAttributes()
                return
            }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes(baseTypingAttributes(), range: range)
            storage.endEditing()
            textView.typingAttributes = baseTypingAttributes()
        }
        
        func apply(_ command: NotebookFormatCommand, to textView: NSTextView) {
            switch command {
            case .bold:
                toggleFontTrait(.boldFontMask, on: textView)
            case .italic:
                toggleFontTrait(.italicFontMask, on: textView)
            case .underline:
                toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, on: textView)
            case .strikethrough:
                toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, on: textView)
            case .highlight(let hex):
                let color = hex.map { NotebookInk.nsColor(hex: $0) } ?? NSColor.clear
                applyAttribute(.backgroundColor, value: color, to: textView)
            case .alignment(let alignment):
                applyParagraphAlignment(alignment, to: textView)
            case .clearFormatting:
                clearFormatting(on: textView)
            case .increaseSize:
                adjustFontSize(by: 1, on: textView)
            case .decreaseSize:
                adjustFontSize(by: -1, on: textView)
            }
            syncContent(from: textView)
        }
        
        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let textView = notification.object as? NSTextView else { return }
            syncContent(from: textView)
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string) else {
                parent.onSelectionChange("")
                return
            }
            parent.onSelectionChange(String(textView.string[swiftRange]))
        }
        
        private func syncContent(from textView: NSTextView) {
            isUpdatingFromView = true
            let plain = textView.string
            var rich: Data?
            if let storage = textView.textStorage, storage.length > 0 {
                let range = NSRange(location: 0, length: storage.length)
                rich = storage.rtf(from: range, documentAttributes: [:])
            }
            parent.plainText = plain
            parent.richContent = rich
            lastRichContent = rich
            parent.onContentChange(plain, rich)
            isUpdatingFromView = false
        }
        
        private func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else {
                toggleTypingFontTrait(trait, on: textView)
                return
            }
            
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let current = (value as? NSFont) ?? parent.formatting.font
                let manager = NSFontManager.shared
                let hasTrait = manager.traits(of: current).contains(trait)
                let updated = hasTrait
                    ? manager.convert(current, toNotHaveTrait: trait)
                    : manager.convert(current, toHaveTrait: trait)
                storage.addAttribute(.font, value: updated, range: subrange)
            }
            storage.endEditing()
        }
        
        private func toggleTypingFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
            var attrs = textView.typingAttributes
            let current = (attrs[.font] as? NSFont) ?? parent.formatting.font
            let manager = NSFontManager.shared
            let hasTrait = manager.traits(of: current).contains(trait)
            let updated = hasTrait
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
            attrs[.font] = updated
            textView.typingAttributes = attrs
        }
        
        private func toggleAttribute(_ key: NSAttributedString.Key, value: Int, on textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else {
                var attrs = textView.typingAttributes
                let current = (attrs[key] as? Int) ?? 0
                attrs[key] = current == 0 ? value : 0
                textView.typingAttributes = attrs
                return
            }
            
            storage.beginEditing()
            var shouldEnable = false
            storage.enumerateAttribute(key, in: range) { existing, _, stop in
                let current = (existing as? Int) ?? 0
                if current == 0 { shouldEnable = true }
                stop.pointee = true
            }
            storage.addAttribute(key, value: shouldEnable ? value : 0, range: range)
            storage.endEditing()
        }
        
        private func applyAttribute(_ key: NSAttributedString.Key, value: Any, to textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else {
                var attrs = textView.typingAttributes
                attrs[key] = value
                textView.typingAttributes = attrs
                return
            }
            storage.addAttribute(key, value: value, range: range)
        }
        
        private func applyParagraphAlignment(_ alignment: NSTextAlignment, to textView: NSTextView) {
            let range = textView.selectedRange()
            guard let storage = textView.textStorage else { return }
            let targetRange = range.length > 0
                ? range
                : NSRange(location: 0, length: storage.length)
            
            storage.enumerateAttribute(.paragraphStyle, in: targetRange) { value, subrange, _ in
                let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? (baseTypingAttributes()[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                style.alignment = alignment
                storage.addAttribute(.paragraphStyle, value: style, range: subrange)
            }
        }
        
        private func clearFormatting(on textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else { return }
            storage.setAttributes(baseTypingAttributes(), range: range)
        }
        
        private func adjustFontSize(by delta: CGFloat, on textView: NSTextView) {
            let newSize = max(10, min(36, parent.formatting.fontSize + Double(delta)))
            parent.formatting.fontSize = newSize
            
            let range = textView.selectedRange()
            guard range.length > 0, let storage = textView.textStorage else {
                textView.typingAttributes = baseTypingAttributes()
                return
            }
            
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let current = (value as? NSFont) ?? parent.formatting.font
                let resized = NSFontManager.shared.convert(current, toSize: CGFloat(newSize))
                storage.addAttribute(.font, value: resized, range: subrange)
            }
            storage.endEditing()
            textView.typingAttributes = baseTypingAttributes()
        }
    }
}

final class NotebookTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    
    override func drawBackground(in rect: NSRect) {
        // Paper lines are drawn by SwiftUI.
    }
}
