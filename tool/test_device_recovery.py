import unittest
from unittest.mock import patch
from pathlib import Path
from device_recovery import checked_package, Driver, PACKAGE


class RecoveryDriverTests(unittest.TestCase):
    def test_refuses_production_and_invalid_apks(self):
        for badging in ["package: name='dev.soaccount.so_account'", '', 'broken']:
            with self.assertRaises(ValueError):
                checked_package(badging)
        checked_package(f"package: name='{PACKAGE}' versionCode='18'")

    def test_kills_actual_process_after_crash_checkpoint(self):
        driver = Driver('adb', 'emulator-5554', Path('.'))
        report = '{"stage":"restore-crash","status":"ready-to-kill"}'
        with patch.object(driver, 'adb', return_value=report) as adb:
            result = driver.run_stage('restore-crash')
            self.assertEqual(result['status'], 'ready-to-kill')
            self.assertEqual(adb.call_args.args, ('shell', 'am', 'force-stop', PACKAGE))

    def test_failure_report_stops_scenario(self):
        driver = Driver('adb', None, Path('.'))
        with patch.object(driver, 'adb', return_value='{"stage":"verify","status":"failed"}'):
            with self.assertRaises(RuntimeError):
                driver.run_stage('verify')


if __name__ == '__main__':
    unittest.main()
