"""JSON-lines OCR/policy worker. All capture, activation and input belong to the host operator."""
from __future__ import annotations
import base64
import io
import json
import math
import queue
import sys
import threading
import time
from PIL import Image
from automation import ForegroundCycle, RetryPolicy
from ocr_engine import Analyzer, annotate


class Bridge:
    def __init__(self, output=None):
        self.stop = threading.Event()
        self.replies = queue.Queue()
        self.sequence = 0
        self.output = output or sys.stdout

    def emit(self, kind, **data):
        self.output.write(json.dumps(dict(kind=kind, **data), ensure_ascii=False) + "\n")
        self.output.flush()

    def receive(self):
        try:
            for line in sys.stdin:
                data = json.loads(line)
                if data.get("stop"):
                    break
                self.replies.put(data)
        finally:
            self.stop.set()

    def rpc(self, action, **data):
        self.sequence += 1
        request_id = self.sequence
        self.emit("operation", id=request_id, action=action, data=data)
        while not self.stop.is_set():
            try:
                reply = self.replies.get(timeout=.1)
            except queue.Empty:
                continue
            if reply.get("id") != request_id:
                continue
            if reply.get("error"):
                raise RuntimeError(reply["error"])
            return reply.get("data", {})
        raise InterruptedError("已停止。")

    @staticmethod
    def image(frame):
        with Image.open(io.BytesIO(base64.b64decode(frame["Png"]))) as source:
            return source.convert("RGB")

    def preview(self, analyzer, config):
        if config.get("image"):
            with Image.open(config["image"]) as source:
                image = source.convert("RGB")
        else:
            self.rpc("Activate")
            if self.stop.wait(.65):
                return
            frame = self.rpc("Capture")
            if not frame.get("Foreground") or not frame.get("Png"):
                raise RuntimeError("游戏不在前台或画面尚未就绪，请重试识别。")
            image = self.image(frame)
        view = analyzer.analyze(image)
        if self.stop.is_set():
            return
        output = io.BytesIO()
        annotate(image, view).save(output, format="PNG")
        self.emit("preview", png=base64.b64encode(output.getvalue()).decode("ascii"),
                  description=view.description, seconds=view.seconds,
                  hits=[dict(text=h.text, score=h.score) for h in view.hits])

    def run(self, analyzer, config, clock=time.monotonic):
        interval = float(config.get("interval", 30))
        if not math.isfinite(interval) or not 1 <= interval <= 86400:
            raise ValueError("重试间隔须为1–86400秒。")
        policy = RetryPolicy(interval, clock(), bool(config.get("auto_stop", True)))
        focus = ForegroundCycle(interval)
        last_log = ""
        while not self.stop.is_set():
            state = self.rpc("State")
            foreground = bool(state.get("Foreground"))
            if not foreground:
                policy.not_visible()
            decision = focus.inspect(policy.deadline, clock(), foreground)
            if decision.action == "activate":
                self.emit("log", text=decision.message)
                try:
                    self.rpc("Activate")
                except RuntimeError as exc:
                    self.emit("log", text=str(exc))
                self.stop.wait(.1)
                continue
            if decision.action == "skip":
                policy.skip_cycle(clock())
                self.emit("log", text=decision.message)
            if decision.action != "ready":
                self.emit("status", text=decision.message)
                self.stop.wait(.1)
                continue
            frame = self.rpc("Capture")
            if not frame.get("Foreground") or not frame.get("Png"):
                policy.not_visible()
                self.stop.wait(.4)
                continue
            view = analyzer.analyze(self.image(frame))
            if self.stop.is_set():
                break
            if not self.rpc("State").get("Foreground"):
                policy.not_visible()
                continue
            decision = policy.inspect(view, clock())
            self.emit("status", text=decision.message)
            if decision.action == "stop":
                self.emit("log", text=decision.message)
                return
            if decision.action in ("finish", "confirm"):
                # Dry runs submit no Click request; the operator also rechecks identity,
                # cancellation, frame age, geometry and occlusion before actual input.
                clicked = bool(config.get("dry_run"))
                if not clicked:
                    hit = decision.hit
                    clicked = bool(self.rpc("Click", X=hit.center[0], Y=hit.center[1],
                        Left=frame["Left"], Top=frame["Top"], Width=frame["Width"],
                        Height=frame["Height"], Stamp=frame["Stamp"]).get("Executed"))
                if clicked and not self.stop.is_set():
                    policy.committed(decision.action, clock())
                    self.emit("counts", finish=policy.finished_attempts, confirm=policy.confirmed)
                    self.emit("log", text=("[试运行：未点击] " if config.get("dry_run") else "") + decision.message)
                elif not self.stop.is_set():
                    policy.skip_cycle(clock())
                    self.emit("log", text="点击已取消：画面过期、窗口变化或被遮挡，等待下个周期。")
            elif decision.message != last_log and "还剩" not in decision.message:
                self.emit("log", text=decision.message)
                last_log = decision.message
            self.stop.wait(.65)


def main():
    bridge = Bridge()
    try:
        config = json.loads(sys.stdin.readline())
        threading.Thread(target=bridge.receive, daemon=True).start()
        bridge.emit("status", text="正在加载本地OCR模型…")
        analyzer = Analyzer()
        if not bridge.stop.is_set():
            if config.get("mode") == "preview":
                bridge.preview(analyzer, config)
            else:
                bridge.run(analyzer, config)
    except InterruptedError:
        pass
    except Exception as exc:
        bridge.emit("error", text=str(exc))
    finally:
        bridge.emit("finished", text="角色创建任务已结束；请核对游戏中的实际结果。")


if __name__ == "__main__":
    main()
