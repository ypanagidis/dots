"""Exercise recovery decisions at the management API boundary."""
import importlib.util
import pathlib
import unittest


path = pathlib.Path(__file__).resolve().parents[1] / "nix/modules/dev/ai/cliproxyapi-reconcile.py"
spec = importlib.util.spec_from_file_location("reconcile", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RecoveryTests(unittest.TestCase):
    def run_case(self, usage, disabled=False, status=200):
        writes = []

        def api(endpoint, data=None, method=None):
            if endpoint == "auth-files":
                return {"files": [{"name": "claude-test.json", "provider": "claude",
                                   "auth_index": "test", "disabled": disabled,
                                   "next_retry_after": "2099-01-01T00:00:00Z"}]}
            if endpoint == "api-call":
                import json
                return {"status_code": status, "body": json.dumps(usage)}
            writes.append((endpoint, data, method))
            return {}

        module.reconcile(api)
        return writes

    def test_reset_account_recovers(self):
        writes = self.run_case({"five_hour": {"utilization": 0}, "seven_day": {"utilization": 0}})
        self.assertEqual([w[1]["disabled"] for w in writes], [True, False])
        self.assertTrue(all(w[0] == "auth-files/status" and w[2] == "PATCH" for w in writes))

    def test_exhausted_windows_remain_blocked(self):
        for window in ("five_hour", "seven_day", "seven_day_opus"):
            usage = {"five_hour": {"utilization": 0}, "seven_day": {"utilization": 0}}
            usage[window] = {"utilization": 100}
            self.assertEqual(self.run_case(usage), [])

    def test_unknown_usage_and_disabled_accounts_are_untouched(self):
        for usage in ({}, {"five_hour": {"utilization": 0}},
                      {"five_hour": {"utilization": 0}, "seven_day": {"utilization": "0"}}):
            self.assertEqual(self.run_case(usage), [])
        healthy = {"five_hour": {"utilization": 0}, "seven_day": {"utilization": 0}}
        self.assertEqual(self.run_case(healthy, disabled=True), [])
        self.assertEqual(self.run_case(healthy, status=401), [])


if __name__ == "__main__":
    unittest.main()
