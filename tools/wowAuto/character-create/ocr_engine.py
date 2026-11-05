"""Local Chinese OCR and button identification; no input or network operations."""
from __future__ import annotations

from dataclasses import dataclass
import re
import time

import numpy as np
from PIL import Image, ImageDraw


@dataclass(frozen=True)
class Hit:
    text: str
    score: float
    box: tuple[int, int, int, int]

    @property
    def center(self) -> tuple[int, int]:
        x1, y1, x2, y2 = self.box
        return ((x1 + x2) // 2, (y1 + y2) // 2)


@dataclass(frozen=True)
class Observation:
    finish: Hit | None
    confirm: Hit | None
    balance: bool
    modal: bool
    hits: tuple[Hit, ...]
    seconds: float = 0.0

    @property
    def description(self) -> str:
        labels = []
        if self.finish:
            labels.append("完成（可点击）")
        if self.balance:
            labels.append("阵营人口不平衡提示")
        if self.confirm:
            labels.append("确定（可点击）")
        return "、".join(labels) or "未识别到目标按钮"


def normalize(text: str) -> str:
    text = text.translate(str.maketrans("陣營確無選擇創", "阵营确无选择创"))
    return re.sub(r"[\W_]+", "", text)


def is_balance_message(text: str) -> bool:
    text = normalize(text)
    return "阵营" in text and (
        "不平衡" in text
        or ("目前无法" in text and ("选择" in text or "创建" in text))
    )


class Analyzer:
    def __init__(self) -> None:
        # All three ONNX models are part of the installed package / bundled exe.
        from rapidocr_onnxruntime import RapidOCR

        self.engine = RapidOCR(intra_op_num_threads=2, inter_op_num_threads=1)

    def _read(self, image: Image.Image, region: tuple[float, float, float, float]) -> list[Hit]:
        w, h = image.size
        rect = tuple(round(v * (w if i % 2 == 0 else h)) for i, v in enumerate(region))
        crop = image.crop(rect).convert("RGB")
        # Upscale smaller clients so gold Chinese glyphs remain legible.
        scale = max(1.0, min(2.5, 1050 / w))
        if scale > 1.01:
            crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        result, _ = self.engine(np.asarray(crop)[:, :, ::-1].copy())
        hits = []
        for quad, text, score in result or []:
            if float(score) < 0.50:
                continue
            xs, ys = zip(*quad)
            box = (round(min(xs) / scale) + rect[0], round(min(ys) / scale) + rect[1],
                   round(max(xs) / scale) + rect[0], round(max(ys) / scale) + rect[1])
            hits.append(Hit(text, float(score), box))
        return hits

    @staticmethod
    def _red_button(image: Image.Image, hit: Hit) -> bool:
        x1, y1, x2, y2 = hit.box
        pad_x = max(12, (x2 - x1) // 2)
        pad_y = max(5, (y2 - y1) // 3)
        patch = np.asarray(image.convert("RGB"))[max(0, y1-pad_y):min(image.height, y2+pad_y),
                                                     max(0, x1-pad_x):min(image.width, x2+pad_x)]
        if patch.size == 0:
            return False
        rgb = patch.astype(np.float32)
        red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        mask = (red > 60) & (red > green * 1.65 + 15) & (red > blue * 1.5 + 15)
        return float(mask.mean()) >= 0.16

    def analyze(self, image: Image.Image) -> Observation:
        started = time.monotonic()
        image = image.convert("RGB")
        # Relative client areas match the user's screenshots and resize with the game.
        middle = self._read(image, (0.20, 0.36, 0.80, 0.72))
        bottom = self._read(image, (0.73, 0.82, 0.995, 0.995))
        balance = is_balance_message("".join(hit.text for hit in middle))
        confirmations = [hit for hit in middle if normalize(hit.text) == "确定"]
        confirm = next((hit for hit in confirmations if self._red_button(image, hit)), None)
        finish = next((hit for hit in bottom if normalize(hit.text) == "完成"
                       and self._red_button(image, hit)), None)
        return Observation(finish, confirm, balance, bool(confirmations) or balance,
                           tuple(middle + bottom), time.monotonic() - started)


def annotate(image: Image.Image, observation: Observation) -> Image.Image:
    image = image.convert("RGB").copy()
    draw = ImageDraw.Draw(image)
    for hit in observation.hits:
        color = "#42e897" if hit in (observation.finish, observation.confirm) else "#ffca55"
        draw.rectangle(hit.box, outline=color, width=max(2, image.width // 550))
    for hit in (observation.finish, observation.confirm):
        if hit:
            x, y = hit.center
            draw.line((x-12, y, x+12, y), fill="#42e897", width=2)
            draw.line((x, y-12, x, y+12), fill="#42e897", width=2)
    return image
