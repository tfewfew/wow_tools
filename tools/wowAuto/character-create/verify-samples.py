"""Read reference screenshots only. Never enumerate windows, capture the screen or click."""
from pathlib import Path
import sys
from PIL import Image
from ocr_engine import Analyzer

samples = Path(sys.argv[1])
analyzer = Analyzer()
for filename, balance in (("01-角色创建.png", False), ("02-阵营人口不平衡.png", True)):
    with Image.open(samples / filename) as original:
        original = original.convert("RGB")
        for width in (original.width, 1280, 960):
            image = original.resize((width, round(original.height * width / original.width)))
            view = analyzer.analyze(image)
            assert (view.balance and view.confirm) if balance else view.finish, (filename, width, view.description)
            print("PASS:", filename, width, view.description)
