//
//  PanelResizeHandle.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct PanelResizeHandle: View {
    @Binding var panelWidth: CGFloat
    var minWidth: CGFloat = 320
    var maxWidth: CGFloat = 920
    
    @State private var dragStartWidth: CGFloat?
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
            
            Capsule()
                .fill(Color.secondary.opacity(isHovering ? 0.45 : 0.22))
                .frame(width: 3, height: 52)
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = panelWidth
                    }
                    let base = dragStartWidth ?? panelWidth
                    panelWidth = min(max(base - value.translation.width, minWidth), maxWidth)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
        .accessibilityLabel("Resize study panel")
    }
    
    @State private var isHovering = false
}
