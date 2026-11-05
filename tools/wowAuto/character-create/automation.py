"""Deterministic retry policy, independent of desktop input and the GUI."""
from __future__ import annotations

from dataclasses import dataclass
from ocr_engine import Hit, Observation


@dataclass(frozen=True)
class Decision:
    action: str
    message: str
    hit: Hit | None = None


class ForegroundCycle:
    """Budget three activation requests per click cycle, starting before it is due."""

    def __init__(self, interval: float):
        self.lead = min(3.0, interval)
        self.retry_gap = self.lead / 3
        self.deadline: float | None = None
        self.attempts = 0
        self.next_attempt = 0.0
        self.settle_until = 0.0

    def inspect(self, deadline: float, now: float, foreground: bool) -> Decision:
        if deadline != self.deadline:
            self.deadline = deadline
            self.attempts = 0
            self.next_attempt = deadline - self.lead
            self.settle_until = 0.0

        # Allow Windows to finish restoring / activating before judging the request.
        if now < self.settle_until:
            return Decision("wait", f"正在等待第 {self.attempts}/3 次前台切换结果…")
        if foreground:
            return Decision("ready", "游戏已在前台。")
        if now < deadline - self.lead:
            return Decision("wait", f"后台等待中，还剩 {deadline - now:.1f} 秒；到时将提前切回游戏。")
        if self.attempts >= 3:
            return Decision("skip", "自动切换前台已尝试 3 次仍未成功，跳过本轮，等待下个周期。")
        if now < self.next_attempt:
            return Decision("wait", f"第 {self.attempts}/3 次前台切换未成功，等待重试…")

        self.attempts += 1
        self.next_attempt = now + self.retry_gap
        self.settle_until = now + min(0.30, self.retry_gap * 0.75)
        return Decision("activate", f"自动切换游戏到前台（第 {self.attempts}/3 次）")


class RetryPolicy:
    def __init__(self, interval: float, now: float, auto_stop: bool = True, missing_timeout: float = 12.0):
        self.interval = interval
        self.deadline = now + interval
        self.auto_stop = auto_stop
        self.missing_timeout = missing_timeout
        self.missing_since: float | None = None
        self.last_confirm = float("-inf")
        self.confirm_attempts = 0
        self.finished_attempts = 0
        self.confirmed = 0
        self.dismissing = False

    def not_visible(self) -> None:
        # A background window is not evidence of a missing creation button.
        self.missing_since = None

    def skip_cycle(self, now: float) -> None:
        # A failed activation cannot leave an overdue click or an exhausted budget.
        self.deadline = max(self.deadline, now) + self.interval
        self.missing_since = None

    def inspect(self, view: Observation, now: float) -> Decision:
        if view.modal:
            self.missing_since = None
            if not view.balance:
                return Decision("stop", "发现其他确认弹窗，已停止，请手动处理。")
            if not view.confirm:
                return Decision("wait", "已识别阵营平衡提示，正在寻找红色“确定”按钮…")
            if now - self.last_confirm < 1.8:
                return Decision("wait", "已点击确定，等待弹窗关闭…")
            if self.confirm_attempts >= 3:
                return Decision("stop", "“确定”已点击 3 次但弹窗仍在，已停止，请检查游戏响应。")
            return Decision("confirm", "阵营人口不平衡 → 点击确定", view.confirm)

        # The previous dialog has disappeared; a future dialog is a new attempt.
        self.confirm_attempts = 0
        self.dismissing = False
        if not view.finish:
            if self.missing_since is None:
                self.missing_since = now
            elapsed = now - self.missing_since
            if self.auto_stop and elapsed >= self.missing_timeout:
                return Decision("stop", "连续 12 秒未识别到可点击的“完成”，已停止；请检查是否已创建成功。")
            return Decision("wait", "未识别到可点击的“完成”，等待界面稳定…")

        self.missing_since = None
        if now < self.deadline:
            return Decision("wait", f"等待下一次尝试，还剩 {self.deadline - now:.1f} 秒")
        return Decision("finish", "间隔已到 → 点击完成", view.finish)

    def committed(self, action: str, now: float) -> None:
        # Advance only after the caller has actually submitted the click.
        self.deadline = now + self.interval
        if action == "finish":
            self.finished_attempts += 1
        elif action == "confirm":
            self.confirmed += 1
            self.confirm_attempts += 1
            self.last_confirm = now
            self.dismissing = True
