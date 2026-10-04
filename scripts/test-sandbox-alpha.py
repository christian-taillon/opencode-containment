#!/usr/bin/env python3
"""Focused standalone alpha tests; no runtime, credentials, or inference."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("alpha", Path(__file__).with_name("sandbox_alpha.py"))
alpha = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alpha)


class AlphaTests(unittest.TestCase):
    def setUp(self):
        Path("/tmp/opencode").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.global_path = self.root / "config.json"
        self.args = argparse.Namespace(no_project_config=False, cpus=None, memory=None,
                                       sbx=None, allow_network=[], env=[])

    def project(self, settings):
        (self.workspace / ".opencode-containment.json").write_text(json.dumps({"sandbox": settings}))

    def test_default_global_project_cli_precedence(self):
        self.global_path.write_text(json.dumps({"sandbox": {"cpus": 4, "memory": "8g"}}))
        self.project({"cpus": 2, "memory": "2g"})
        self.args.cpus = 3
        config, sources = alpha.settings(self.global_path, self.workspace, self.args)
        self.assertEqual((config["cpus"], config["memory"]), (3, "2g"))
        self.assertEqual(len(sources), 3)

    def test_project_cannot_authorize_host_access(self):
        for settings in ({"network_allow": ["host.docker.internal:11434"]},
                         {"environment": {"GH_TOKEN": "fake"}}, {"sbx": "/evil"},
                         {"template": "evil"}):
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                self.project(settings)
                alpha.settings(self.global_path, self.workspace, self.args)

    def test_project_resources_bounded_and_cli_can_approve(self):
        self.project({"cpus": 8, "memory": "8g"})
        with self.assertRaises(ValueError):
            alpha.settings(self.global_path, self.workspace, self.args)
        self.args.cpus, self.args.memory = 8, "8g"
        self.assertEqual(alpha.settings(self.global_path, self.workspace, self.args)[0]["cpus"], 8)

    def test_no_project_config_bypasses_bad_project(self):
        self.project({"sbx": "/evil"})
        self.args.no_project_config = True
        self.assertEqual(alpha.settings(self.global_path, self.workspace, self.args)[0]["cpus"], 2)

    def test_environment_explicit_only_and_reserved_names(self):
        with patch.dict(os.environ, {"GH_TOKEN": "test-only"}):
            self.assertEqual(alpha.settings(self.global_path, self.workspace, self.args)[0]["environment"], {})
            self.args.env = ["GH_TOKEN"]
            self.assertEqual(alpha.settings(self.global_path, self.workspace, self.args)[0]["environment"], {"GH_TOKEN": "test-only"})
        for key in ("SSH_AUTH_SOCK", "HOME", "BASH_ENV", "OPENCODE_CONFIG", "MCP_GATEWAY_URL", "LD_PRELOAD"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                alpha.validate({"environment": {key: "bad"}})

    def test_bad_types_and_network_patterns_rejected(self):
        for settings in ({"cpus": True}, {"memory": "1m"}, {"network_allow": ["**"]},
                         {"network_allow": ["localhost:99999"]}, {"environment": {"KEY": "line\nbreak"}},
                         {"template": None}, {"unknown": True}):
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                alpha.validate(settings)

    def test_json_symlinks_and_unknown_root_rejected(self):
        source = self.root / "source.json"
        source.write_text('{}')
        self.global_path.symlink_to(source)
        with self.assertRaises(ValueError):
            alpha.read_json(self.global_path)
        self.global_path.unlink()
        self.global_path.write_text('{"host_commands":[]}')
        with self.assertRaises(ValueError):
            alpha.settings(self.global_path, self.workspace, self.args)

    def test_workspace_must_be_descendant_and_not_sensitive(self):
        with patch.object(Path, "cwd", return_value=self.root):
            self.assertEqual(alpha.workspace_path(self.workspace), self.workspace)
            with self.assertRaises(ValueError):
                alpha.workspace_path(self.root.parent)
            sensitive = self.root / ".ssh"
            sensitive.mkdir()
            with self.assertRaises(ValueError):
                alpha.workspace_path(sensitive)

    def test_runtime_strips_credentials_agent_and_injection_vars(self):
        with patch.dict(os.environ, {"GH_TOKEN": "fake", "SSH_AUTH_SOCK": "/fake", "DOCKER_HOST": "bad", "SBX_CLOUD": "1"}):
            runtime = alpha.Runtime("/usr/bin/true")
        self.assertFalse(set(runtime.environment) & {"GH_TOKEN", "SSH_AUTH_SOCK", "DOCKER_HOST", "SBX_CLOUD"})

    def test_replacement_or_workspace_change_refuses_ownership(self):
        runtime = alpha.Runtime("/usr/bin/true")
        record = {"name": "alpha", "id": "original", "workspace": str(self.workspace)}
        runtime.find = Mock(return_value={"id": "original", "workspaces": [str(self.workspace)]})
        runtime.owned(record)
        for found in (None, {"id": "replacement", "workspaces": [str(self.workspace)]},
                      {"id": "original", "workspaces": ["/"]}):
            runtime.find.return_value = found
            with self.assertRaises(ValueError):
                runtime.owned(record)

    def test_interruption_forces_stop_even_with_keep_running(self):
        runtime = Mock(executable="/usr/bin/true", environment={})
        record = {"name": "alpha", "workspace": str(self.workspace)}
        process = Mock(returncode=-9)
        process.wait.side_effect = [KeyboardInterrupt, subprocess.TimeoutExpired("exec", 2), 0]
        process.poll.return_value = None
        with patch.object(alpha.subprocess, "Popen", return_value=process):
            self.assertEqual(alpha.run_client(runtime, record, ["--standalone"], True), 130)
        process.terminate.assert_called_once()
        process.kill.assert_called_once()
        runtime.call.assert_called_once_with("stop", "alpha")

    def test_normal_success_stops_by_default_and_can_retain(self):
        record = {"name": "alpha", "workspace": str(self.workspace)}
        for keep_running in (False, True):
            with self.subTest(keep_running=keep_running):
                runtime = Mock(executable="/usr/bin/true", environment={})
                process = Mock(returncode=0)
                process.wait.return_value = 0
                process.poll.return_value = 0
                with patch.object(alpha.subprocess, "Popen", return_value=process):
                    self.assertEqual(alpha.run_client(runtime, record, [], keep_running), 0)
                self.assertEqual(runtime.call.call_count, 0 if keep_running else 1)

    def test_client_launch_failure_stops_even_with_keep_running(self):
        runtime = Mock(executable="/usr/bin/true", environment={})
        record = {"name": "alpha", "workspace": str(self.workspace)}
        with patch.object(alpha.subprocess, "Popen", side_effect=OSError("fixture")):
            with self.assertRaises(OSError):
                alpha.run_client(runtime, record, [], True)
        runtime.call.assert_called_once_with("stop", "alpha")

    def test_cached_binary_integrity_rejected(self):
        pin = alpha.read_json(alpha.ROOT / "config/opencode2-pin.json")
        target = self.root / "clients" / pin["version"] / "opencode2"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"modified")
        target.with_suffix(".json").write_text('{"sha256":"incorrect"}')
        with self.assertRaisesRegex(ValueError, "integrity"):
            alpha.client(self.root)

    def test_effective_config_redacts_environment_values(self):
        config = {**alpha.DEFAULTS, "environment": {"TEST_KEY": "do-not-print"}}
        visible = alpha.visible_config(config, ["defaults"], self.global_path, self.workspace)
        self.assertNotIn("do-not-print", json.dumps(visible))
        self.assertEqual(visible["sandbox"]["environment"], ["TEST_KEY"])

    def test_cleanup_restores_signal_handlers_when_stop_fails(self):
        runtime = Mock(executable="/usr/bin/true", environment={})
        runtime.call.side_effect = RuntimeError("stop failed")
        record = {"name": "alpha", "workspace": str(self.workspace)}
        process = Mock(returncode=0)
        process.wait.return_value = 0
        process.poll.return_value = 0
        with patch.object(alpha.subprocess, "Popen", return_value=process), patch.object(alpha.signal, "signal") as signals:
            with self.assertRaisesRegex(RuntimeError, "stop failed"):
                alpha.run_client(runtime, record, [], False)
        self.assertEqual(signals.call_count, 6)
        self.assertEqual(signals.call_args_list[-2].args[0], alpha.signal.SIGINT)
        self.assertEqual(signals.call_args_list[-1].args[0], alpha.signal.SIGTERM)

    def test_cleanup_preflight_does_not_block_on_sharing_or_diagnostics(self):
        runtime = Mock(executable="/usr/bin/true")
        runtime.call.return_value = "sbx version: v0.46.0 fixture"
        def reply(*args):
            if args == ("daemon", "status", "--json"):
                return {"status": "running", "socket": "/test/socket"}
            if args == ("diagnose", "--json"):
                return {"checks": [{"name": "Authentication", "status": "fail", "message": "expired"}]}
            raise AssertionError(args)
        runtime.json.side_effect = reply
        self.assertEqual(alpha.preflight(runtime, False, False)["socket"], "/test/socket")
        with self.assertRaisesRegex(ValueError, "expired"):
            alpha.preflight(runtime, False)


if __name__ == "__main__":
    unittest.main(verbosity=1)
