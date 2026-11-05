"""Offline protocol/policy tests. Capture and input are represented by Python dictionaries."""
import base64
import io
import json
import unittest
from types import SimpleNamespace
from PIL import Image
from automation import ForegroundCycle, RetryPolicy
from bridge import Bridge
from ocr_engine import Hit, Observation

READY = Observation(Hit("完成", .99, (750, 530, 820, 560)), None, False, False, ())
BALANCE = Observation(None, Hit("确定", .99, (400, 300, 480, 340)), True, True, ())


class ClockStop:
    def __init__(self, clock, until=9):
        self.clock, self.until, self.stopped = clock, until, False

    def set(self):
        self.stopped = True

    def is_set(self):
        return self.stopped or self.clock[0] >= self.until

    def wait(self, seconds):
        self.clock[0] += seconds
        return self.is_set()


class BridgeTests(unittest.TestCase):
    def simulate(self, *, dry=False, foreground=True, view=READY, until=9, cancel_ocr=False, click=True):
        clock, actions, events = [0.0], [], []
        png = io.BytesIO()
        Image.new("RGB", (900, 600), "black").save(png, format="PNG")
        frame = dict(Foreground=True, Png=base64.b64encode(png.getvalue()).decode(),
                     Left=0, Top=0, Width=900, Height=600, Stamp=100)
        bridge = Bridge(io.StringIO())
        bridge.stop = ClockStop(clock, until)
        bridge.emit = lambda kind, **data: events.append((kind, data))

        def rpc(action, **data):
            actions.append((action, clock[0], data))
            if action == "State":
                return dict(Foreground=foreground)
            if action == "Capture":
                return frame
            return dict(Executed=click)

        def analyze(_):
            if cancel_ocr:
                bridge.stop.set()
            return view

        bridge.rpc = rpc
        bridge.run(SimpleNamespace(analyze=analyze), dict(interval=2, dry_run=dry), clock=lambda: clock[0])
        return actions, events

    def test_full_first_interval_and_repeated_clicks(self):
        actions, events = self.simulate()
        clicks = [a for a in actions if a[0] == "Click"]
        self.assertTrue(clicks)
        self.assertGreaterEqual(clicks[0][1], 2)
        for previous, current in zip(clicks, clicks[1:]):
            self.assertGreaterEqual(current[1] - previous[1], 2)
        self.assertEqual(clicks[0][2]["Width"], 900)
        self.assertTrue(any(kind == "counts" for kind, _ in events))

    def test_dry_run_never_requests_click(self):
        actions, events = self.simulate(dry=True)
        self.assertFalse(any(a[0] == "Click" for a in actions))
        self.assertTrue(any(kind == "counts" for kind, _ in events))

    def test_focus_failures_skip_cycles_and_recover_budget(self):
        actions, events = self.simulate(foreground=False)
        self.assertGreater(len([a for a in actions if a[0] == "Activate"]), 3)
        self.assertFalse(any(a[0] == "Click" for a in actions))
        self.assertTrue(any("跳过本轮" in data.get("text", "") for _, data in events))

    def test_stop_after_ocr_submits_no_click(self):
        actions, _ = self.simulate(cancel_ocr=True)
        self.assertFalse(any(a[0] == "Click" for a in actions))

    def test_rejected_click_does_not_count_success(self):
        _, events = self.simulate(click=False)
        self.assertFalse(any(kind == "counts" for kind, _ in events))

    def test_balance_modal_is_limited_to_three_confirmations(self):
        actions, events = self.simulate(view=BALANCE, until=20)
        self.assertEqual(len([a for a in actions if a[0] == "Click"]), 3)
        self.assertTrue(any("已点击 3 次" in data.get("text", "") for _, data in events))

    def test_other_modal_stops_without_click(self):
        actions, _ = self.simulate(view=Observation(None, BALANCE.confirm, False, True, ()))
        self.assertFalse(any(a[0] == "Click" for a in actions))

    def test_invalid_intervals(self):
        for interval in (0, .5, 86401, float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                Bridge(io.StringIO()).run(None, dict(interval=interval))

    def test_rpc_ignores_stale_replies(self):
        output = io.StringIO()
        bridge = Bridge(output)
        bridge.replies.put(dict(id=99, data={}))
        bridge.replies.put(dict(id=1, data=dict(Foreground=True)))
        self.assertTrue(bridge.rpc("State")["Foreground"])
        self.assertEqual(json.loads(output.getvalue())["action"], "State")

    def test_rpc_cancellation(self):
        bridge = Bridge(io.StringIO())
        bridge.stop.set()
        with self.assertRaises(InterruptedError):
            bridge.rpc("Click")

    def test_missing_button_timeout_is_configurable(self):
        empty = Observation(None, None, False, False, ())
        policy = RetryPolicy(30, 0)
        self.assertEqual(policy.inspect(empty, 0).action, "wait")
        self.assertEqual(policy.inspect(empty, 12).action, "stop")
        policy = RetryPolicy(30, 0, False)
        self.assertEqual(policy.inspect(empty, 0).action, "wait")
        self.assertEqual(policy.inspect(empty, 100).action, "wait")


if __name__ == "__main__":
    unittest.main()
