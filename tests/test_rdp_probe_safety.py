"""Failure injection for probe recovery, without importing/running device code."""
import ast
from pathlib import Path
import shlex
import unittest

SOURCE=Path(__file__).with_name('run-rdp-usability.py')

class RdpProbeRecoveryTests(unittest.TestCase):
    def recovery(self, rejected):
        calls=[]
        def remote(command):
            calls.append(command)
            if rejected(command):
                raise OSError('Injected recovery I/O failure')
            return b''
        module=ast.parse(SOURCE.read_text())
        functions=[node for node in module.body if isinstance(node,ast.FunctionDef) and node.name in ('rollback_apps','fallback_recovery')]
        context=dict(remote=remote,q=shlex.quote,remote_base='/private/fixture',apps='/apps',qrr='/qrr/window.qml',main_qrr='/qrr/main.qml',ids={'ui':'test-ui','engine':'test-engine','helper':'test-helper'},token='owned-run')
        exec(compile(ast.Module(body=functions,type_ignores=[]),str(SOURCE),'exec'),context)
        errors=context['fallback_recovery']()
        return calls,errors

    def assert_restart_attempted(self,calls):
        self.assertTrue(any('systemctl start xochitl' in command for command in calls))
        self.assertTrue(any('/old-appload.qml' in command for command in calls))
        self.assertTrue(any('/xochitl.conf' in command for command in calls))

    def test_app_rollback_failure_still_restores_settings_and_restarts(self):
        calls,errors=self.recovery(lambda command:'/previous-apps/paperrdp' in command)
        self.assertTrue(errors)
        self.assert_restart_attempted(calls)
        self.assertTrue(any('/previous-apps/paperrdp-profile' in command for command in calls))

    def test_one_probe_cleanup_failure_does_not_skip_other_cleanup_or_restart(self):
        calls,errors=self.recovery(lambda command:'/test-ui/probe-run-id' in command)
        self.assertTrue(errors)
        self.assert_restart_attempted(calls)
        self.assertTrue(any('/test-helper/probe-run-id' in command for command in calls))

    def test_stop_or_config_failure_still_attempts_all_recovery_steps(self):
        calls,errors=self.recovery(lambda command:command=='systemctl stop xochitl' or '/xochitl.conf' in command)
        self.assertGreaterEqual(len(errors),2)
        self.assert_restart_attempted(calls)

    def test_successful_recovery_reports_no_errors(self):
        calls,errors=self.recovery(lambda command:False)
        self.assertEqual(errors,[])
        self.assert_restart_attempted(calls)
        for name in ['test-ui','test-engine','test-helper']:
            self.assertTrue(any(name+'/probe-run-id' in command and 'owned-run' in command for command in calls))

if __name__=='__main__':unittest.main()
