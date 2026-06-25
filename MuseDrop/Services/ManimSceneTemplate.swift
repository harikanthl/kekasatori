//
//  ManimSceneTemplate.swift
//  MuseDrop
//
//  Bundled Manim scene used when rendering notebook math animations.
//  Embedded as source so rendering still works if the .py file is missing from the app bundle.
//

import Foundation

enum ManimSceneTemplate {
    static let fileName = "musedrop_scene.py"
    
    /// Embedded copy of Resources/manim/musedrop_scene.py — keep in sync when editing that file.
    static let embeddedSource = #"""
    # MuseDrop notebook → Manim bridge scene.
    
    from __future__ import annotations
    
    import json
    from pathlib import Path
    
    from manim import *
    
    
    class MuseDropFormulaScene(Scene):
        def construct(self):
            job_path = Path(__file__).parent / "job.json"
            job = json.loads(job_path.read_text(encoding="utf-8"))
    
            latex = job["latex"]
            style = job.get("style", "write")
            transform_to = job.get("transform_to")
    
            bg = job.get("background", "#1a1a2e")
            self.camera.background_color = bg
    
            title_text = job.get("title")
            if title_text:
                title = Text(title_text, font_size=28, color=GRAY_B)
                title.to_edge(UP, buff=0.4)
                self.add(title)
    
            formula = MathTex(latex)
            max_width = config.frame_width - 1.2
            if formula.width > max_width:
                formula.scale_to_fit_width(max_width)
    
            if style == "transform" and transform_to:
                target = MathTex(transform_to)
                if target.width > max_width:
                    target.scale_to_fit_width(max_width)
                self.play(Write(formula))
                self.wait(0.4)
                self.play(TransformMatchingTex(formula, target))
                self.wait(1.6)
                return
    
            if style == "fadeIn":
                self.play(FadeIn(formula, shift=UP * 0.15))
            elif style == "grow":
                self.play(GrowFromCenter(formula))
            else:
                self.play(Write(formula))
    
            self.wait(2)
    """#
    
    static func writeScene(to destination: URL) throws {
        if let bundled = PathUtils.getManimSceneTemplateURL() {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: bundled, to: destination)
            return
        }
        
        try embeddedSource.write(to: destination, atomically: true, encoding: .utf8)
        LogService.shared.warning("Manim scene template not found in bundle; wrote embedded fallback")
    }
}
