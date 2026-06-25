"""MuseDrop notebook → rich Manim scenes (attention, matrices, atoms, graphs, derivations)."""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from manim import *


def _load_job() -> dict:
    job_path = Path(__file__).parent / "job.json"
    return json.loads(job_path.read_text(encoding="utf-8"))


def _make_function(expr: str):
    """Evaluate a numpy expression safely in x."""
    allowed = {
        "x": None,
        "np": np,
        "sin": np.sin,
        "cos": np.cos,
        "tan": np.tan,
        "sqrt": np.sqrt,
        "abs": np.abs,
        "exp": np.exp,
        "log": np.log,
        "pi": np.pi,
        "e": math.e,
    }

    # Defense-in-depth denylist: reject anything that could reach attributes,
    # subscripts, dunders, lambdas, imports, or slices. Plain math like
    # "sin(x)" or "x**2+3*x" contains none of these.
    forbidden = ("_", ".", "[", "]", "lambda", "import", ":")
    if any(token in expr for token in forbidden):
        def safe_default(_x_val: float) -> float:
            return 0.0

        return safe_default

    def fn(x_val: float) -> float:
        env = dict(allowed)
        env["x"] = x_val
        result = eval(expr, {"__builtins__": {}}, env)
        if isinstance(result, (int, float)):
            return float(result)
        return float(result)

    return fn


def _fit_math(mobj: Mobject, max_width: float | None = None) -> Mobject:
    width = max_width or (config.frame_width - 1.2)
    if mobj.width > width:
        mobj.scale_to_fit_width(width)
    return mobj


def _matmul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    rows, inner, cols = len(a), len(b), len(b[0])
    out = [[0.0] * cols for _ in range(rows)]
    for i in range(rows):
        for j in range(cols):
            for k in range(inner):
                out[i][j] += a[i][k] * b[k][j]
    return out


def _shell_electrons(atomic_number: int) -> list[int]:
    capacities = [2, 8, 8, 18, 18, 32]
    remaining = max(1, atomic_number)
    shells: list[int] = []
    for cap in capacities:
        if remaining <= 0:
            break
        shells.append(min(remaining, cap))
        remaining -= cap
    return shells


def _format_matrix(values: list[list[float]]) -> list[list[str]]:
    return [[f"{v:.1f}" if abs(v - round(v)) > 1e-6 else str(int(round(v))) for v in row] for row in values]


class MuseDropFormulaScene(Scene):
    def construct(self):
        job = _load_job()
        self.camera.background_color = job.get("background", "#0d1117")

        scene_type = job.get("scene_type", "auto")
        if scene_type == "auto":
            scene_type = self._resolve_auto(job)

        dispatch = {
            "attention": self._attention_scene,
            "neural_network": self._neural_network_scene,
            "convolution": self._convolution_scene,
            "gradient_descent": self._gradient_descent_scene,
            "matrix_ops": self._matrix_ops_scene,
            "atom_model": self._atom_model_scene,
            "quantum_wave": self._quantum_wave_scene,
            "wave_physics": self._wave_physics_scene,
            "fourier_series": self._fourier_series_scene,
            "orbital_mechanics": self._orbital_mechanics_scene,
            "spacetime": self._spacetime_scene,
            "function_graph": self._function_graph,
            "equation_graph": self._equation_graph,
            "derivation": self._derivation,
            "formula": self._formula,
        }
        handler = dispatch.get(scene_type, self._formula)
        handler(job)

    def _resolve_auto(self, job: dict) -> str:
        latex = (job.get("latex") or "").lower()
        title = (job.get("title") or "").lower()
        combined = f"{latex} {title}"

        if any(k in combined for k in ("attention", "softmax", "transformer", "qkv")):
            return "attention"
        if any(k in combined for k in ("spacetime", "einstein", "curvature", "black hole", "relativity")):
            return "spacetime"
        if any(k in combined for k in ("kepler", "orbit", "planet", "solar")):
            return "orbital_mechanics"
        if any(k in combined for k in ("schrodinger", "schrödinger", "wavefunction", "\\psi", "hbar", "quantum")):
            return "quantum_wave"
        if any(k in combined for k in ("convolution", "cnn", "kernel", "conv2d")):
            return "convolution"
        if any(k in combined for k in ("neural", "perceptron", "mlp", "backprop", "relu")):
            return "neural_network"
        if any(k in combined for k in ("gradient", "sgd", "optimizer", "nabla")):
            return "gradient_descent"
        if any(k in combined for k in ("fourier", "harmonic", "spectrum")):
            return "fourier_series"
        if "wave" in combined and "quantum" not in combined:
            return "wave_physics"
        if any(k in combined for k in ("atom", "electron", "bohr", "orbital")):
            return "atom_model"
        if "matrix" in combined or "\\begin{" in latex:
            return "matrix_ops"
        steps = job.get("steps") or []
        if len(steps) >= 2:
            return "derivation"
        if job.get("function_expr"):
            return "equation_graph"
        return "formula"

    # ------------------------------------------------------------------ #
    # Attention (Transformer / "Attention Is All You Need")
    # ------------------------------------------------------------------ #

    def _attention_scene(self, job: dict):
        tokens = job.get("attention_tokens") or ["Attention", "is", "all", "you", "need"]
        n = min(len(tokens), 5)
        tokens = tokens[:n]

        latex = job.get("latex") or (
            r"\text{Attention}(Q,K,V)=\mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right)V"
        )
        formula = MathTex(latex, font_size=34)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula, config.frame_width - 0.6)
        self.play(Write(formula), run_time=1.5)

        token_labels = VGroup(
            *[Text(t, font_size=22, color=GRAY_A) for t in tokens]
        ).arrange(RIGHT, buff=0.55)
        token_labels.next_to(formula, DOWN, buff=0.55)
        self.play(FadeIn(token_labels, shift=UP * 0.1))

        dim = 3
        rng = np.random.default_rng(42)
        x_vals = rng.uniform(-0.5, 0.5, size=(n, dim))
        x_matrix = Matrix(_format_matrix(x_vals.tolist()), h_buff=0.65, v_buff=0.45).scale(0.55)
        x_label = MathTex("X", color=YELLOW).scale(0.7).next_to(x_matrix, LEFT, buff=0.2)
        embed_group = VGroup(x_label, x_matrix).next_to(token_labels, DOWN, buff=0.45)
        self.play(FadeIn(embed_group, shift=DOWN * 0.1))

        wq = Matrix(_format_matrix(rng.uniform(0, 1, (dim, dim)).tolist()), h_buff=0.55).scale(0.42)
        wk = Matrix(_format_matrix(rng.uniform(0, 1, (dim, dim)).tolist()), h_buff=0.55).scale(0.42)
        wv = Matrix(_format_matrix(rng.uniform(0, 1, (dim, dim)).tolist()), h_buff=0.55).scale(0.42)

        q_lbl = MathTex("Q", color=BLUE).scale(0.65).next_to(wq, UP, buff=0.08)
        k_lbl = MathTex("K", color=GREEN).scale(0.65).next_to(wk, UP, buff=0.08)
        v_lbl = MathTex("V", color=RED).scale(0.65).next_to(wv, UP, buff=0.08)

        qkv = VGroup(
            VGroup(q_lbl, wq),
            VGroup(k_lbl, wk),
            VGroup(v_lbl, wv),
        ).arrange(RIGHT, buff=0.55)
        qkv.next_to(embed_group, DOWN, buff=0.5)
        self.play(
            LaggedStart(
                *[FadeIn(m, shift=UP * 0.08) for m in qkv],
                lag_ratio=0.25,
            )
        )

        q_vals = x_vals @ rng.uniform(0, 1, (dim, dim))
        k_vals = x_vals @ rng.uniform(0, 1, (dim, dim))
        scores = (q_vals @ k_vals.T) / math.sqrt(dim)
        scores = scores - scores.max(axis=1, keepdims=True)
        exp_scores = np.exp(scores)
        weights = exp_scores / exp_scores.sum(axis=1, keepdims=True)

        score_tex = MathTex(r"QK^\top / \sqrt{d_k}", font_size=28, color=TEAL)
        score_tex.next_to(qkv, DOWN, buff=0.35)
        self.play(Write(score_tex))

        heatmap = self._attention_heatmap(weights, tokens)
        heatmap.next_to(score_tex, DOWN, buff=0.3)
        self.play(FadeIn(heatmap, scale=0.95), run_time=1.4)

        softmax_lbl = MathTex(r"\mathrm{softmax}", font_size=30, color=MAROON)
        softmax_lbl.next_to(heatmap, DOWN, buff=0.2)
        self.play(Write(softmax_lbl))

        out_arrow = Arrow(heatmap.get_right(), heatmap.get_right() + RIGHT * 0.8, buff=0.1, color=YELLOW)
        out_lbl = MathTex(r"\times V", font_size=28, color=YELLOW).next_to(out_arrow, RIGHT, buff=0.1)
        self.play(GrowArrow(out_arrow), FadeIn(out_lbl))
        self.wait(1.2)

    def _attention_heatmap(self, weights: np.ndarray, tokens: list[str]) -> VGroup:
        n = len(tokens)
        cell = 0.42
        grid = VGroup()
        col_labels = VGroup(
            *[Text(t, font_size=16, color=GRAY_B) for t in tokens]
        ).arrange(RIGHT, buff=cell)
        row_labels = VGroup(
            *[Text(t, font_size=16, color=GRAY_B) for t in tokens]
        ).arrange(DOWN, buff=cell)

        for i in range(n):
            for j in range(n):
                w = float(weights[i, j])
                color = interpolate_color(BLUE_E, YELLOW, w)
                sq = Square(side_length=cell, fill_color=color, fill_opacity=0.92, stroke_width=0.8)
                sq.move_to(np.array([j * cell, -i * cell, 0]))
                val = DecimalNumber(w, num_decimal_places=2, font_size=14, color=WHITE)
                val.move_to(sq)
                grid.add(VGroup(sq, val))

        col_labels.next_to(grid, UP, buff=0.12)
        row_labels.next_to(grid, LEFT, buff=0.12)
        return VGroup(col_labels, row_labels, grid)

    # ------------------------------------------------------------------ #
    # Matrix multiplication
    # ------------------------------------------------------------------ #

    def _matrix_ops_scene(self, job: dict):
        a_vals = job.get("matrix_a") or [[1, 2], [3, 4]]
        b_vals = job.get("matrix_b") or [[2, 1], [0, 3]]
        c_vals = _matmul(a_vals, b_vals)

        latex = job.get("latex")
        if latex:
            title = MathTex(latex, font_size=36)
            title.to_edge(UP, buff=0.35)
            _fit_math(title)
            self.play(Write(title))

        a = Matrix(_format_matrix(a_vals), h_buff=0.9, v_buff=0.7).scale(0.75)
        times = MathTex(r"\times", font_size=48)
        b = Matrix(_format_matrix(b_vals), h_buff=0.9, v_buff=0.7).scale(0.75)
        eq = MathTex("=", font_size=48)
        c = Matrix(_format_matrix(c_vals), h_buff=0.9, v_buff=0.7).scale(0.75)

        row = VGroup(a, times, b, eq, c).arrange(RIGHT, buff=0.35)
        row.move_to(ORIGIN + DOWN * 0.15)

        a_lbl = MathTex("A", color=BLUE).scale(0.7).next_to(a, UP, buff=0.15)
        b_lbl = MathTex("B", color=GREEN).scale(0.7).next_to(b, UP, buff=0.15)
        c_lbl = MathTex("C", color=YELLOW).scale(0.7).next_to(c, UP, buff=0.15)

        self.play(Write(a_lbl), Write(a))
        self.play(Write(times), Write(b_lbl), Write(b))

        pulse = SurroundingRectangle(VGroup(a, b), color=YELLOW, buff=0.12, stroke_width=2)
        self.play(Create(pulse), run_time=0.6)
        self.play(FadeOut(pulse))

        self.play(Write(eq), FadeIn(c), Write(c_lbl))
        self.wait(1.2)

    # ------------------------------------------------------------------ #
    # Bohr atom model
    # ------------------------------------------------------------------ #

    def _atom_model_scene(self, job: dict):
        symbol = job.get("element_symbol") or "H"
        atomic_number = int(job.get("atomic_number") or 1)
        shells = _shell_electrons(atomic_number)

        latex = job.get("latex") or r"E_n = -\frac{R_H}{n^2}"
        formula = MathTex(latex, font_size=36)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.play(Write(formula))

        nucleus = Circle(radius=0.38, color=RED, fill_color=RED, fill_opacity=0.85, stroke_width=2)
        z_label = MathTex(f"{symbol}", color=WHITE).scale(0.9)
        z_sub = MathTex(f"Z={atomic_number}", font_size=24, color=GRAY_A).next_to(nucleus, DOWN, buff=0.12)
        nucleus_group = VGroup(nucleus, z_label.move_to(nucleus)).shift(DOWN * 0.3)
        self.play(GrowFromCenter(nucleus_group), FadeIn(z_sub))

        proton_note = Text(f"{atomic_number} proton{'s' if atomic_number != 1 else ''}", font_size=20, color=GRAY_B)
        proton_note.next_to(z_sub, DOWN, buff=0.15)
        self.play(FadeIn(proton_note))

        all_orbits = VGroup()
        all_electrons = VGroup()
        for shell_idx, count in enumerate(shells):
            radius = 0.95 + shell_idx * 0.75
            orbit = Circle(radius=radius, color=GRAY_B, stroke_opacity=0.45, stroke_width=1.2)
            orbit.move_to(nucleus_group.get_center())
            all_orbits.add(orbit)

            shell_e = VGroup()
            for e_idx in range(count):
                angle = TAU * e_idx / max(count, 1)
                dot = Dot(color=BLUE_C, radius=0.09)
                dot.move_to(orbit.point_at_angle(angle))
                shell_e.add(dot)
            all_electrons.add(shell_e)

        self.play(LaggedStart(*[Create(o) for o in all_orbits], lag_ratio=0.15))
        self.play(LaggedStart(*[FadeIn(e, scale=0.5) for e in all_electrons], lag_ratio=0.1))

        shell_label = Text(
            f"Shells: {', '.join(str(c) for c in shells)} e⁻",
            font_size=22,
            color=TEAL,
        ).to_edge(DOWN, buff=0.45)
        self.play(FadeIn(shell_label))

        rotations = [
            Rotate(shell, angle=TAU, about_point=nucleus_group.get_center(), rate_func=linear)
            for shell in all_electrons
        ]
        self.play(
            AnimationGroup(*rotations, lag_ratio=0.0),
            run_time=4,
            rate_func=linear,
        )
        self.wait(0.8)

    # ------------------------------------------------------------------ #
    # Neural network (ManimML / 3B1B style feedforward)
    # ------------------------------------------------------------------ #

    def _build_neural_network(self, layers: list[int]) -> tuple[VGroup, list[VGroup]]:
        layer_groups: list[VGroup] = []
        neuron_radius = 0.14
        v_buff = 0.55
        h_buff = 1.6

        for size in layers:
            neurons = VGroup(
                *[Circle(radius=neuron_radius, color=BLUE_C, fill_opacity=0.35, stroke_width=1.5) for _ in range(size)]
            ).arrange(DOWN, buff=v_buff)
            layer_groups.append(neurons)

        network = VGroup(*layer_groups).arrange(RIGHT, buff=h_buff)
        edges = VGroup()
        for i in range(len(layer_groups) - 1):
            for n1 in layer_groups[i]:
                for n2 in layer_groups[i + 1]:
                    edges.add(
                        Line(n1.get_center(), n2.get_center(), stroke_width=0.6, stroke_opacity=0.25, color=GRAY_B)
                    )
        return VGroup(edges, network), layer_groups

    def _neural_network_scene(self, job: dict):
        layers = job.get("neural_layers") or [3, 5, 4, 2]
        latex = job.get("latex") or r"y = \sigma(Wx + b)"
        formula = MathTex(latex, font_size=34)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.play(Write(formula))

        net_group, layer_groups = self._build_neural_network(layers)
        net_group.scale(0.85).next_to(formula, DOWN, buff=0.45)
        edges, layers_mob = net_group[0], net_group[1]

        labels = ["Input", "Hidden", "Hidden", "Output"]
        layer_labels = VGroup()
        for idx, layer in enumerate(layer_groups):
            name = labels[min(idx, len(labels) - 1)] if idx == 0 or idx == len(layer_groups) - 1 else f"H{idx}"
            lbl = Text(name, font_size=18, color=GRAY_A).next_to(layer, DOWN, buff=0.2)
            layer_labels.add(lbl)

        self.play(Create(edges), LaggedStart(*[FadeIn(l, scale=0.6) for l in layer_groups], lag_ratio=0.2))
        self.play(FadeIn(layer_labels))

        pulse = Dot(color=YELLOW, radius=0.1).move_to(layer_groups[0][0])
        self.play(FadeIn(pulse, scale=0.5))
        for layer in layer_groups[1:]:
            target = layer[len(layer) // 2]
            self.play(pulse.animate.move_to(target.get_center()), run_time=0.55)
            self.play(Flash(target, color=YELLOW, flash_radius=0.35), run_time=0.35)
        self.wait(0.8)

    # ------------------------------------------------------------------ #
    # Convolution (CNN feature map + sliding kernel)
    # ------------------------------------------------------------------ #

    def _convolution_scene(self, job: dict):
        kernel_size = int(job.get("convolution_kernel_size") or 3)
        latex = job.get("latex") or r"(I * K)(i,j) = \sum_{m,n} I(i+m,j+n)\,K(m,n)"
        formula = MathTex(latex, font_size=30)
        formula.to_edge(UP, buff=0.3)
        _fit_math(formula, config.frame_width - 0.5)
        self.play(Write(formula))

        grid_n = 6
        cell = 0.42
        rng = np.random.default_rng(7)
        values = rng.integers(0, 9, size=(grid_n, grid_n))

        input_cells = VGroup()
        for i in range(grid_n):
            for j in range(grid_n):
                val = int(values[i, j])
                color = interpolate_color(BLUE_E, TEAL, val / 8)
                sq = Square(side_length=cell, fill_color=color, fill_opacity=0.85, stroke_width=0.6)
                sq.move_to(np.array([(j - grid_n / 2) * cell, (grid_n / 2 - i) * cell, 0]))
                num = Text(str(val), font_size=16, color=WHITE).move_to(sq)
                input_cells.add(VGroup(sq, num))
        input_cells.scale(0.9).next_to(formula, DOWN, buff=0.4).shift(LEFT * 2.2)
        input_lbl = Text("Input", font_size=20, color=GRAY_A).next_to(input_cells, UP, buff=0.12)

        kernel_vals = np.array([[1, 0, -1], [2, 0, -2], [1, 0, -1]]) if kernel_size == 3 else np.ones((kernel_size, kernel_size))
        kernel_cells = VGroup()
        for i in range(kernel_size):
            for j in range(kernel_size):
                sq = Square(side_length=cell * 0.85, color=YELLOW, stroke_width=2)
                sq.move_to(np.array([(j - kernel_size / 2) * cell * 0.85, (kernel_size / 2 - i) * cell * 0.85, 0]))
                num = Text(str(int(kernel_vals[i, j])), font_size=14, color=YELLOW).move_to(sq)
                kernel_cells.add(VGroup(sq, num))
        kernel_cells.next_to(input_cells, RIGHT, buff=1.2)
        kernel_lbl = Text("Kernel K", font_size=20, color=YELLOW).next_to(kernel_cells, UP, buff=0.12)

        self.play(FadeIn(input_lbl), FadeIn(input_cells))
        self.play(FadeIn(kernel_lbl), FadeIn(kernel_cells))

        highlight = Square(side_length=cell * kernel_size * 0.95, color=YELLOW, stroke_width=3)
        highlight.move_to(input_cells[0][0].get_center())
        self.play(Create(highlight))
        for pos in [3, 9, 15, 21]:
            if pos < len(input_cells):
                self.play(highlight.animate.move_to(input_cells[pos][0].get_center()), run_time=0.45)
        self.play(FadeOut(highlight))
        self.wait(0.6)

    # ------------------------------------------------------------------ #
    # Gradient descent (loss landscape + descent path)
    # ------------------------------------------------------------------ #

    def _gradient_descent_scene(self, job: dict):
        lr = float(job.get("learning_rate") or 0.1)
        latex = job.get("latex") or r"\theta_{t+1} = \theta_t - \eta \nabla_\theta \mathcal{L}(\theta)"
        formula = MathTex(latex, font_size=32)
        formula.to_edge(UP, buff=0.3)
        _fit_math(formula)
        self.play(Write(formula))

        axes = Axes(
            x_range=[-2, 2, 1],
            y_range=[-2, 2, 1],
            x_length=6.5,
            y_length=5,
            axis_config={"include_tip": False, "font_size": 20},
        ).shift(DOWN * 0.25)
        axes_labels = axes.get_axis_labels(MathTex(r"\theta_1"), MathTex(r"\theta_2"))

        def loss_surface(x, y):
            return (x - 0.8) ** 2 + 2 * (y - 0.3) ** 2

        _ = loss_surface
        contours = VGroup()
        for level in [0.5, 1.0, 2.0, 3.5, 5.0]:
            contour = axes.plot_parametric_curve(
                lambda t, lv=level: np.array([
                    0.8 + np.sqrt(lv / 2) * np.cos(t),
                    0.3 + np.sqrt(lv / 4) * np.sin(t),
                    0,
                ]),
                t_range=[0, TAU],
                color=interpolate_color(BLUE_E, TEAL, level / 5),
                stroke_opacity=0.65,
            )
            contours.add(contour)

        self.play(Create(axes), Write(axes_labels))
        self.play(LaggedStart(*[Create(c) for c in contours], lag_ratio=0.12))

        theta = np.array([-1.4, -0.8])
        dot = Dot(color=YELLOW, radius=0.09).move_to(axes.c2p(theta[0], theta[1]))
        trail = TracedPath(dot.get_center, stroke_color=YELLOW, stroke_width=2.5)
        self.play(FadeIn(dot))
        self.add(trail)

        for _ in range(10):
            grad = np.array([2 * (theta[0] - 0.8), 4 * (theta[1] - 0.3)])
            step = lr * grad
            arrow = Arrow(
                axes.c2p(theta[0], theta[1]),
                axes.c2p(theta[0] - step[0], theta[1] - step[1]),
                color=RED,
                buff=0.05,
                stroke_width=2.5,
                max_tip_length_to_length_ratio=0.18,
            )
            self.play(GrowArrow(arrow), run_time=0.22)
            theta = theta - step
            self.play(dot.animate.move_to(axes.c2p(theta[0], theta[1])), run_time=0.3)
            self.play(FadeOut(arrow))

        self.wait(0.8)

    # ------------------------------------------------------------------ #
    # Quantum wavefunction
    # ------------------------------------------------------------------ #

    def _quantum_wave_scene(self, job: dict):
        mode = job.get("quantum_mode") or "box"
        latex = job.get("latex") or r"\psi_n(x)=\sqrt{\frac{2}{L}}\sin\!\left(\frac{n\pi x}{L}\right)"
        formula = MathTex(latex, font_size=30)
        formula.to_edge(UP, buff=0.3)
        _fit_math(formula)
        self.play(Write(formula))

        axes = Axes(
            x_range=[0, 6, 1],
            y_range=[-1.2, 1.2, 0.5],
            x_length=9,
            y_length=3.5,
            axis_config={"include_tip": False, "font_size": 20},
        ).shift(DOWN * 0.2)
        psi_label = MathTex(r"\psi(x)", color=BLUE).next_to(axes, UP, buff=0.1).shift(RIGHT * 3)
        prob_label = MathTex(r"|\psi|^2", color=YELLOW).next_to(psi_label, RIGHT, buff=0.4)

        L = 5.0
        n = 2

        def psi_fn(x):
            if mode == "gaussian":
                sigma = 0.6
                x0 = L / 2
                return np.exp(-((x - x0) ** 2) / (2 * sigma**2))
            return np.sqrt(2 / L) * np.sin(n * PI * x / L)

        psi_graph = axes.plot(psi_fn, x_range=[0.2, L - 0.2], color=BLUE)
        prob_graph = axes.plot(lambda x: psi_fn(x) ** 2, x_range=[0.2, L - 0.2], color=YELLOW)

        walls = VGroup(
            Line(axes.c2p(0, -1.2), axes.c2p(0, 1.2), color=RED, stroke_width=4),
            Line(axes.c2p(L, -1.2), axes.c2p(L, 1.2), color=RED, stroke_width=4),
        )

        self.play(Create(axes), Write(psi_label), Write(prob_label))
        if mode == "box":
            self.play(Create(walls))
        self.play(Create(psi_graph), run_time=1.5)
        self.play(Create(prob_graph), run_time=1.2)

        tracker = ValueTracker(0)

        def update_psi(mob):
            t = tracker.get_value()
            phase = np.cos(2 * t)
            new_curve = axes.plot(lambda x: psi_fn(x) * phase, x_range=[0.2, L - 0.2], color=BLUE)
            mob.become(new_curve)

        psi_graph.add_updater(update_psi)
        self.add(psi_graph)
        self.play(tracker.animate.set_value(TAU), run_time=3, rate_func=linear)
        psi_graph.remove_updater(update_psi)
        self.wait(0.6)

    # ------------------------------------------------------------------ #
    # Wave physics (traveling wave)
    # ------------------------------------------------------------------ #

    def _wave_physics_scene(self, job: dict):
        latex = job.get("latex") or r"E(x,t)=E_0\sin(kx-\omega t)"
        formula = MathTex(latex, font_size=34)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.play(Write(formula))

        axes = Axes(
            x_range=[0, 4 * PI, PI],
            y_range=[-1.5, 1.5, 0.5],
            x_length=9,
            y_length=3.2,
            axis_config={"include_tip": False, "font_size": 20},
        ).shift(DOWN * 0.15)
        x_lbl = MathTex("x").next_to(axes.x_axis, RIGHT)
        self.play(Create(axes), FadeIn(x_lbl))

        k, omega = 1.0, 2.0
        tracker = ValueTracker(0)

        wave = always_redraw(
            lambda: axes.plot(
                lambda x: np.sin(k * x - omega * tracker.get_value()),
                x_range=[0, 4 * PI],
                color=BLUE,
            )
        )
        self.play(FadeIn(wave))
        self.play(tracker.animate.set_value(2 * PI), run_time=3, rate_func=linear)

        crest_dot = always_redraw(
            lambda: Dot(color=YELLOW, radius=0.08).move_to(
                axes.c2p((omega * tracker.get_value()) / k % (2 * PI), 1)
            )
        )
        self.play(FadeIn(crest_dot))
        self.play(tracker.animate.set_value(4 * PI), run_time=2, rate_func=linear)
        self.wait(0.5)

    # ------------------------------------------------------------------ #
    # Fourier series (harmonics → square wave)
    # ------------------------------------------------------------------ #

    def _fourier_series_scene(self, job: dict):
        n_terms = int(job.get("fourier_terms") or 7)
        latex = job.get("latex") or r"f(x)=\sum_{n=1}^{\infty}\frac{\sin((2n-1)x)}{2n-1}"
        formula = MathTex(latex, font_size=30)
        formula.to_edge(UP, buff=0.3)
        _fit_math(formula)
        self.play(Write(formula))

        axes = Axes(
            x_range=[-PI, PI, PI / 2],
            y_range=[-1.5, 1.5, 0.5],
            x_length=9,
            y_length=3.5,
            axis_config={"include_tip": False, "font_size": 20},
        ).shift(DOWN * 0.15)

        def partial_sum(x, terms):
            total = 0.0
            for n in range(1, terms + 1):
                k = 2 * n - 1
                total += np.sin(k * x) / k
            return (4 / PI) * total

        self.play(Create(axes))
        current_graph = axes.plot(lambda x: partial_sum(x, 1), x_range=[-PI, PI], color=BLUE)
        self.play(Create(current_graph))

        for terms in range(2, n_terms + 1):
            new_graph = axes.plot(lambda x, t=terms: partial_sum(x, t), x_range=[-PI, PI], color=BLUE)
            term_lbl = MathTex(f"n={terms}", font_size=24, color=YELLOW).to_corner(DR)
            self.play(Transform(current_graph, new_graph), FadeIn(term_lbl), run_time=0.7)
            self.play(FadeOut(term_lbl), run_time=0.2)

        square_hint = DashedVMobject(
            axes.plot(lambda x: 1 if x > 0 else -1, x_range=[-PI + 0.05, PI - 0.05], color=RED),
            num_dashes=20,
        )
        self.play(Create(square_hint), run_time=1)
        self.wait(0.8)

    # ------------------------------------------------------------------ #
    # Orbital mechanics (Kepler ellipse)
    # ------------------------------------------------------------------ #

    def _orbital_mechanics_scene(self, job: dict):
        ecc = float(job.get("orbital_eccentricity") or 0.45)
        latex = job.get("latex") or r"F = G\frac{m_1 m_2}{r^2}"
        formula = MathTex(latex, font_size=34)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.play(Write(formula))

        a, b = 3.0, 3.0 * math.sqrt(1 - ecc**2)
        center = DOWN * 0.2
        orbit = Ellipse(width=2 * a, height=2 * b, color=GRAY_B, stroke_width=1.5).move_to(center)

        star = Dot(color=YELLOW, radius=0.22).move_to(center + LEFT * a * ecc)
        glow = Circle(radius=0.35, color=YELLOW, fill_opacity=0.15, stroke_width=0).move_to(star)
        planet = Dot(color=BLUE_C, radius=0.12).move_to(orbit.point_at_angle(0))

        self.play(FadeIn(glow), GrowFromCenter(star))
        self.play(Create(orbit), FadeIn(planet))

        trail = TracedPath(planet.get_center, stroke_color=BLUE_C, stroke_width=2, dissipating_time=2)

        tracker = ValueTracker(0)

        def move_planet(mob):
            mob.move_to(orbit.point_at_angle(tracker.get_value() * TAU))

        planet.add_updater(move_planet)
        self.add(trail, planet)
        self.play(tracker.animate.set_value(1), run_time=5, rate_func=linear)
        planet.clear_updaters()

        kepler_lbl = Text("Equal areas in equal times", font_size=20, color=TEAL).to_edge(DOWN, buff=0.4)
        self.play(FadeIn(kepler_lbl))
        self.wait(0.6)

    # ------------------------------------------------------------------ #
    # Spacetime curvature (GR grid bending)
    # ------------------------------------------------------------------ #

    def _spacetime_scene(self, job: dict):
        latex = job.get("latex") or r"G_{\mu\nu}=8\pi T_{\mu\nu}"
        formula = MathTex(latex, font_size=34)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.play(Write(formula))

        grid_lines = VGroup()
        x_rng = np.linspace(-5, 5, 14)
        y_rng = np.linspace(-2.5, 2.5, 8)

        def warp(x, y):
            r2 = x**2 + y**2
            return -1.2 * np.exp(-r2 / 3.5)

        for x in x_rng:
            pts = [np.array([x, y, warp(x, y)]) for y in y_rng]
            grid_lines.add(VMobject().set_points_as_corners(pts).set_stroke(GRAY_B, 0.8, opacity=0.55))
        for y in y_rng:
            pts = [np.array([x, y, warp(x, y)]) for x in x_rng]
            grid_lines.add(VMobject().set_points_as_corners(pts).set_stroke(GRAY_B, 0.8, opacity=0.55))

        grid_lines.scale(0.55).shift(DOWN * 0.25)
        mass = Circle(radius=0.28, color=YELLOW, fill_color=YELLOW, fill_opacity=0.9).move_to(DOWN * 0.25)
        mass_lbl = Text("Mass", font_size=18, color=BLACK).move_to(mass)

        self.play(LaggedStart(*[Create(l) for l in grid_lines], lag_ratio=0.02), run_time=1.5)
        self.play(GrowFromCenter(mass), FadeIn(mass_lbl))

        geodesic_pts = []
        for t in np.linspace(-4, 4, 80):
            y = 0.8 * np.tanh(t * 0.5)
            z = warp(t * 0.55, y * 0.55)
            geodesic_pts.append(np.array([t * 0.55, y * 0.55, z]))
        geodesic = VMobject(color=RED, stroke_width=3).set_points_smoothly(geodesic_pts)

        photon = Dot(color=RED, radius=0.08).move_to(geodesic_pts[0])
        self.play(Create(geodesic), FadeIn(photon))
        self.play(MoveAlongPath(photon, geodesic), run_time=3, rate_func=linear)
        self.wait(0.6)

    # ------------------------------------------------------------------ #
    # Classic scenes
    # ------------------------------------------------------------------ #

    def _formula(self, job: dict):
        latex = job["latex"]
        style = job.get("style", "write")
        transform_to = job.get("transform_to")
        color_vars = job.get("color_variables") or []

        palette = [YELLOW, BLUE, GREEN, RED, TEAL, MAROON]
        color_map = {}
        for index, var in enumerate(color_vars[:6]):
            color_map[var] = palette[index]

        if color_map:
            formula = MathTex(latex, tex_to_color_map=color_map)
        else:
            formula = MathTex(latex)

        _fit_math(formula)

        if style == "transform" and transform_to:
            target = MathTex(transform_to)
            _fit_math(target)
            self.play(Write(formula))
            self.wait(0.3)
            self.play(TransformMatchingTex(formula, target))
            self.wait(1.5)
            return

        if style == "fadeIn":
            self.play(FadeIn(formula, shift=UP * 0.15))
        elif style == "grow":
            self.play(GrowFromCenter(formula))
        else:
            self.play(Write(formula))
        self.wait(2)

    def _function_graph(self, job: dict):
        expr = job["function_expr"]
        fn = _make_function(expr)

        x_min = float(job.get("x_min", -3))
        x_max = float(job.get("x_max", 3))
        y_min = float(job.get("y_min", -2))
        y_max = float(job.get("y_max", 8))

        axes = Axes(
            x_range=[x_min, x_max, 1],
            y_range=[y_min, y_max, 1],
            x_length=9,
            y_length=5,
            axis_config={"include_numbers": True, "font_size": 24},
            tips=False,
        )
        axes.center().shift(DOWN * 0.2)

        graph = axes.plot(fn, x_range=[x_min, x_max], color=BLUE, use_smoothing=True)
        graph_label = axes.get_graph_label(graph, MathTex(job.get("latex", expr)), direction=UR)

        self.play(Create(axes), run_time=1.2)
        self.play(Create(graph), Write(graph_label), run_time=2)

        dot = Dot(color=YELLOW, radius=0.08)
        dot.move_to(axes.c2p(x_min, fn(x_min)))
        self.play(FadeIn(dot, scale=0.5))

        tracker = ValueTracker(x_min)

        def update_dot(mob):
            x_val = tracker.get_value()
            mob.move_to(axes.c2p(x_val, fn(x_val)))

        dot.add_updater(update_dot)
        self.play(tracker.animate.set_value(x_max), run_time=3, rate_func=linear)
        dot.remove_updater(update_dot)
        self.wait(0.8)

    def _equation_graph(self, job: dict):
        expr = job["function_expr"]
        fn = _make_function(expr)

        x_min = float(job.get("x_min", -3))
        x_max = float(job.get("x_max", 3))
        y_min = float(job.get("y_min", -2))
        y_max = float(job.get("y_max", 8))

        color_vars = job.get("color_variables") or []
        palette = [YELLOW, BLUE, GREEN, RED, TEAL, MAROON]
        color_map = {var: palette[i] for i, var in enumerate(color_vars[:6])}

        if color_map:
            title = MathTex(job["latex"], tex_to_color_map=color_map, font_size=42)
        else:
            title = MathTex(job["latex"], font_size=42)
        title.to_edge(UP, buff=0.35)
        _fit_math(title, config.frame_width - 0.8)

        axes = Axes(
            x_range=[x_min, x_max, 1],
            y_range=[y_min, y_max, 1],
            x_length=8.5,
            y_length=4.2,
            axis_config={"include_numbers": True, "font_size": 22},
            tips=False,
        )
        axes.next_to(title, DOWN, buff=0.45)

        graph = axes.plot(fn, x_range=[x_min, x_max], color=BLUE)
        area = axes.get_area(graph, x_range=[x_min, 0], color=BLUE, opacity=0.18)

        self.play(Write(title))
        self.play(Create(axes), run_time=1)
        self.play(Create(graph), FadeIn(area), run_time=1.8)

        tracker = ValueTracker(x_min)
        dot = Dot(color=YELLOW, radius=0.07)
        dot.move_to(axes.c2p(x_min, fn(x_min)))

        def update_dot(mob):
            x_val = tracker.get_value()
            mob.move_to(axes.c2p(x_val, fn(x_val)))

        dot.add_updater(update_dot)
        self.add(dot)
        self.play(tracker.animate.set_value(x_max), run_time=2.5, rate_func=smooth)
        dot.remove_updater(update_dot)
        self.wait(0.8)

    def _derivation(self, job: dict):
        steps = job.get("steps") or [job["latex"]]
        equations = [MathTex(step) for step in steps]
        for eq in equations:
            _fit_math(eq)

        current = equations[0]
        self.play(Write(current))
        self.wait(0.4)

        for next_eq in equations[1:]:
            next_eq.move_to(current)
            self.play(TransformMatchingTex(current, next_eq))
            current = next_eq
            self.wait(0.7)

        self.wait(1.2)


class MuseDrop3DScene(ThreeDScene):
    """OpenGL ThreeDScene for loss surfaces, orbits, spacetime, and quantum landscapes."""

    def construct(self):
        job = _load_job()
        self.camera.background_color = job.get("background", "#0d1117")

        scene_type = job.get("scene_type", "gradient_descent")
        dispatch = {
            "gradient_descent": self._gradient_descent_3d,
            "spacetime": self._spacetime_3d,
            "orbital_mechanics": self._orbital_mechanics_3d,
            "quantum_wave": self._quantum_wave_3d,
        }
        handler = dispatch.get(scene_type, self._gradient_descent_3d)
        handler(job)

    def _gradient_descent_3d(self, job: dict):
        lr = float(job.get("learning_rate") or 0.08)
        latex = job.get("latex") or r"\theta_{t+1} = \theta_t - \eta \nabla_\theta \mathcal{L}(\theta)"
        formula = MathTex(latex, font_size=30)
        formula.to_edge(UP, buff=0.35)
        _fit_math(formula)
        self.add_fixed_in_frame_mobjects(formula)

        self.set_camera_orientation(phi=68 * DEGREES, theta=-42 * DEGREES, zoom=0.9)

        axes = ThreeDAxes(x_range=[-2, 2, 1], y_range=[-2, 2, 1], z_range=[0, 7, 1], x_length=6, y_length=6, z_length=3.5)

        def loss(u, v):
            return (u - 0.8) ** 2 + 2 * (v - 0.3) ** 2 + 0.2

        surface = axes.plot_surface(
            loss,
            u_range=[-2, 2],
            v_range=[-2, 2],
            resolution=(22, 22),
            colorscale=[BLUE_E, TEAL, GREEN, YELLOW, RED],
        )
        surface.set_opacity(0.82)

        self.play(Write(formula), Create(axes), Create(surface), run_time=2)

        theta = np.array([-1.5, -0.9])
        z0 = loss(theta[0], theta[1])
        dot = Dot3D(point=axes.c2p(theta[0], theta[1], z0), color=YELLOW, radius=0.08)
        self.add(dot)

        for _ in range(12):
            grad = np.array([2 * (theta[0] - 0.8), 4 * (theta[1] - 0.3)])
            step = lr * grad
            theta = theta - step
            z = loss(theta[0], theta[1])
            target = axes.c2p(theta[0], theta[1], z)
            self.play(dot.animate.move_to(target), run_time=0.45)

        self.begin_ambient_camera_rotation(rate=0.15)
        self.wait(2.5)
        self.stop_ambient_camera_rotation()
        self.wait(0.5)

    def _spacetime_3d(self, job: dict):
        latex = job.get("latex") or r"G_{\mu\nu}=8\pi T_{\mu\nu}"
        formula = MathTex(latex, font_size=32)
        formula.to_edge(UP)
        _fit_math(formula)
        self.add_fixed_in_frame_mobjects(formula)
        self.set_camera_orientation(phi=62 * DEGREES, theta=-35 * DEGREES)

        def warp(x, y):
            r2 = x**2 + y**2
            return -1.4 * np.exp(-r2 / 4.0)

        surface = Surface(
            lambda u, v: np.array([u * 0.55, v * 0.55, warp(u, v)]),
            u_range=[-4, 4],
            v_range=[-3, 3],
            resolution=(24, 18),
            fill_opacity=0.75,
        )
        surface.set_color_by_gradient(BLUE_E, TEAL, BLACK)

        mass = Sphere(radius=0.22, color=YELLOW, resolution=(12, 12)).move_to(np.array([0, 0, warp(0, 0) + 0.1]))

        self.play(Write(formula), Create(surface), FadeIn(mass))
        self.begin_ambient_camera_rotation(rate=0.12)
        self.wait(3)
        self.stop_ambient_camera_rotation()

    def _orbital_mechanics_3d(self, job: dict):
        ecc = float(job.get("orbital_eccentricity") or 0.45)
        latex = job.get("latex") or r"F = G\frac{m_1 m_2}{r^2}"
        formula = MathTex(latex, font_size=32)
        formula.to_edge(UP)
        _fit_math(formula)
        self.add_fixed_in_frame_mobjects(formula)
        self.set_camera_orientation(phi=60 * DEGREES, theta=-30 * DEGREES)

        a, b = 3.0, 3.0 * math.sqrt(max(0.05, 1 - ecc**2))
        orbit = Ellipse(width=2 * a, height=2 * b, color=BLUE_C)
        star = Sphere(radius=0.25, color=YELLOW, resolution=(14, 14)).shift(LEFT * a * ecc)
        planet = Sphere(radius=0.12, color=BLUE, resolution=(10, 10)).move_to(orbit.point_at_angle(0))

        self.play(Write(formula), Create(orbit), FadeIn(star), FadeIn(planet))
        tracker = ValueTracker(0)

        def move_planet(mob):
            mob.move_to(orbit.point_at_angle(tracker.get_value() * TAU))

        planet.add_updater(move_planet)
        self.add(planet)
        self.play(tracker.animate.set_value(1), run_time=5, rate_func=linear)
        planet.clear_updaters()
        self.begin_ambient_camera_rotation(rate=0.1)
        self.wait(1.5)
        self.stop_ambient_camera_rotation()

    def _quantum_wave_3d(self, job: dict):
        latex = job.get("latex") or r"|\psi(x,y)|^2"
        formula = MathTex(latex, font_size=32)
        formula.to_edge(UP)
        _fit_math(formula)
        self.add_fixed_in_frame_mobjects(formula)
        self.set_camera_orientation(phi=70 * DEGREES, theta=-40 * DEGREES)

        def psi_sq(x, y):
            return np.exp(-(x**2 + y**2) / 1.2) * (np.cos(2 * x) ** 2)

        axes = ThreeDAxes(x_range=[-3, 3], y_range=[-3, 3], z_range=[0, 1.2, 0.3], x_length=6, y_length=6, z_length=2.5)
        surface = axes.plot_surface(
            psi_sq,
            u_range=[-3, 3],
            v_range=[-3, 3],
            resolution=(28, 28),
            colorscale=[BLUE_E, PURPLE, YELLOW],
        )
        surface.set_opacity(0.88)

        self.play(Write(formula), Create(axes), Create(surface), run_time=2)
        self.begin_ambient_camera_rotation(rate=0.18)
        self.wait(3)
        self.stop_ambient_camera_rotation()
