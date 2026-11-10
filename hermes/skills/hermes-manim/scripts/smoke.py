from manim import *


class Smoke(Scene):
    def construct(self):
        title = Text("hermes-manim", font_size=48)
        formula = MathTex(r"e^{i\pi} + 1 = 0")
        circle = Circle(color=BLUE)
        self.play(Write(title))
        self.play(title.animate.to_edge(UP))
        self.play(Write(formula))
        self.play(Create(circle))
        self.wait(0.5)
