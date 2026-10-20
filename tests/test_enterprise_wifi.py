"""802.1X settings and profile lifecycle without changing the host network."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location(
    'enterprise_wifi', Path(__file__).resolve().parents[1] / 'services/enterprise_wifi.py')
wifi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wifi)


class EnterpriseTests(unittest.TestCase):
    def setUp(self):
        self.data = dict(ssid='School: WiFi', identity='student@example.org', password='x',
                         domain='radius.example.org', eap='peap', phase2='mschapv2')
        self.variant = lambda kind, value: value

    def settings(self, **changes):
        return wifi.settings_for(dict(self.data, **changes), self.variant)[1]

    def test_peap_short_password_and_system_trust(self):
        settings = self.settings()
        auth = settings['802-1x']
        self.assertEqual(settings['802-11-wireless']['ssid'], list(b'School: WiFi'))
        self.assertEqual(settings['802-11-wireless-security']['key-mgmt'], 'wpa-eap')
        self.assertEqual(auth['eap'], ['peap'])
        self.assertEqual(auth['password'], 'x')
        self.assertEqual(auth['phase2-auth'], 'mschapv2')
        self.assertEqual(auth['domain-suffix-match'], 'radius.example.org')
        self.assertTrue(auth['system-ca-certs'])
        self.assertFalse(settings['connection']['autoconnect'])
        self.assertNotIn('bssid', settings['802-11-wireless'])

    def test_username_password_only_uses_system_trust_without_domain_gate(self):
        data = dict(self.data)
        data.pop('domain')
        _, settings = wifi.settings_for(data, self.variant)
        auth = settings['802-1x']
        self.assertTrue(auth['system-ca-certs'])
        self.assertNotIn('domain-suffix-match', auth)
        self.assertEqual(auth['eap'], ['peap'])
        self.assertEqual(auth['phase2-auth'], 'mschapv2')

    def test_ttls_custom_ca_anonymous_identity_hidden_and_literal_password(self):
        with tempfile.NamedTemporaryFile(suffix='.pem') as ca:
            settings = self.settings(eap='ttls', phase2='pap', caCert=ca.name,
                                     anonymousIdentity='anonymous@example.org', hidden=True,
                                     password=' "\\\n$(touch /tmp/not-run)')
        auth = settings['802-1x']
        self.assertFalse(auth['system-ca-certs'])
        self.assertEqual(bytes(auth['ca-cert']), ('file://' + ca.name + '\0').encode())
        self.assertEqual(auth['phase2-auth'], 'pap')
        self.assertEqual(auth['anonymous-identity'], 'anonymous@example.org')
        self.assertEqual(auth['password'], ' "\\\n$(touch /tmp/not-run)')
        self.assertTrue(settings['802-11-wireless']['hidden'])

    def test_invalid_settings_are_rejected_before_dbus(self):
        for changes in ({'identity': ''}, {'password': ''}, {'domain': 'bad domain'},
                        {'eap': 'tls'}, {'phase2': 'pap'}, {'ssid': 'ü' * 17},
                        {'password': 'bad\0value'}, {'caCert': '/missing/school-ca.pem'}):
            with self.subTest(changes=changes), self.assertRaises((ValueError, OSError)):
                self.settings(**changes)

    def run_connection(self, result=None, error=None, save_error=False):
        bus = Mock()
        response = Mock()
        response.unpack.return_value = ('/new/profile/42',)
        bus.call_sync.return_value = response
        if save_error:
            bus.call_sync.side_effect = [response, RuntimeError('save failed')]
        runner = Mock(return_value=types.SimpleNamespace(returncode=result or 0), side_effect=error)
        gio = types.SimpleNamespace(DBusCallFlags=types.SimpleNamespace(NONE=0))
        glib = types.SimpleNamespace(Variant=self.variant, Error=RuntimeError)
        try:
            value = wifi.connect(self.data, bus, gio, glib, run=runner)
        except subprocess.TimeoutExpired:
            value = {'success': False}
        return value, bus, runner

    def test_success_saves_and_never_places_credentials_in_argv(self):
        result, bus, runner = self.run_connection()
        self.assertEqual(result, {'success': True, 'saved': True})
        self.assertEqual([c.args[3] for c in bus.call_sync.call_args_list],
                         ['AddConnectionUnsaved', 'Update'])
        argv = runner.call_args.args[0]
        self.assertEqual(argv[:7], ['nmcli', '--wait', '90', 'connection', 'up', 'uuid', argv[6]])
        self.assertNotIn(self.data['password'], argv)
        self.assertNotIn(self.data['identity'], argv)
        self.assertTrue(bus.call_sync.call_args.args[4][0]['connection']['autoconnect'])

    def test_failure_and_timeout_delete_only_new_profile(self):
        for opts in ({'result': 4}, {'error': subprocess.TimeoutExpired('nmcli', 100)}):
            with self.subTest(opts=opts):
                result, bus, _ = self.run_connection(**opts)
                self.assertFalse(result['success'])
                self.assertEqual([c.args[3] for c in bus.call_sync.call_args_list],
                                 ['AddConnectionUnsaved', 'Delete'])
                self.assertEqual(bus.call_sync.call_args.args[1], '/new/profile/42')

    def test_save_failure_keeps_active_connection_and_reports_it(self):
        result, bus, _ = self.run_connection(save_error=True)
        self.assertEqual(result, {'success': True, 'saved': False})
        self.assertEqual(bus.call_sync.call_count, 2)

    def test_settings_pass_networkmanager_validation_when_available(self):
        try:
            import gi
            gi.require_version('NM', '1.0')
            from gi.repository import GLib, NM
        except (ImportError, ValueError):
            self.skipTest('libnm introspection not installed')
        for eap, phase2 in (('peap', 'mschapv2'), ('ttls', 'mschapv2'), ('ttls', 'pap')):
            _, settings = wifi.settings_for(dict(self.data, eap=eap, phase2=phase2), GLib.Variant)
            connection = NM.SimpleConnection.new_from_dbus(GLib.Variant('a{sa{sv}}', settings))
            self.assertTrue(connection.verify())
        _, settings = wifi.settings_for(dict(self.data, domain=''), GLib.Variant)
        self.assertTrue(NM.SimpleConnection.new_from_dbus(
            GLib.Variant('a{sa{sv}}', settings)).verify())


if __name__ == '__main__':
    unittest.main()
