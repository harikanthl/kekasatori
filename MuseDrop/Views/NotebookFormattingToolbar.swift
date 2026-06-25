//
//  NotebookFormattingToolbar.swift
//  MuseDrop
//

import SwiftUI

struct NotebookFormattingToolbar: View {
    @Binding var formatting: NotebookPageFormatting
    let onCommand: (NotebookFormatCommand) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                styleButton(icon: "bold", help: "Bold (⌘B)") {
                    onCommand(.bold)
                }
                styleButton(icon: "italic", help: "Italic (⌘I)") {
                    onCommand(.italic)
                }
                styleButton(icon: "underline", help: "Underline (⌘U)") {
                    onCommand(.underline)
                }
                styleButton(icon: "strikethrough", help: "Strikethrough") {
                    onCommand(.strikethrough)
                }
                
                toolbarDivider
                
                fontFamilyMenu
                fontSizeControls
                inkColorMenu
                highlightMenu
                
                toolbarDivider
                
                styleButton(icon: "text.alignleft", help: "Align left") {
                    onCommand(.alignment(.left))
                }
                styleButton(icon: "text.aligncenter", help: "Align center") {
                    onCommand(.alignment(.center))
                }
                styleButton(icon: "text.alignright", help: "Align right") {
                    onCommand(.alignment(.right))
                }
                
                toolbarDivider
                
                styleButton(icon: "textformat", help: "Clear formatting") {
                    onCommand(.clearFormatting)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.04))
    }
    
    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
    
    private func styleButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
    
    private var fontFamilyMenu: some View {
        Menu {
            ForEach(NotebookFontFamily.allCases) { family in
                Button {
                    formatting.fontFamily = family
                } label: {
                    if formatting.fontFamily == family {
                        Label(family.title, systemImage: "checkmark")
                    } else {
                        Text(family.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(formatting.fontFamily.title)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Font family")
    }
    
    private var fontSizeControls: some View {
        HStack(spacing: 2) {
            Button {
                onCommand(.decreaseSize)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("Decrease size")
            
            Text("\(Int(formatting.fontSize))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 24)
            
            Button {
                onCommand(.increaseSize)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("Increase size")
        }
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }
    
    private var inkColorMenu: some View {
        Menu {
            ForEach(NotebookInk.palette, id: \.hex) { item in
                Button {
                    formatting.inkColorHex = item.hex
                } label: {
                    Label(item.name, systemImage: formatting.inkColorHex == item.hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(NotebookInk.swiftUIColor(hex: formatting.inkColorHex))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    }
                Text("Ink")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Ink color")
    }
    
    private var highlightMenu: some View {
        Menu {
            Button("None") {
                onCommand(.highlight(nil))
            }
            ForEach(NotebookInk.highlightPalette, id: \.hex) { item in
                Button(item.name) {
                    onCommand(.highlight(item.hex))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "highlighter")
                    .font(.caption.weight(.semibold))
                Text("Highlight")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Highlight color")
    }
}
