"""Pair one selected BlueZ device, then establish its service connection."""
import sys

import gi
from gi.repository import Gio, GLib

DEVICE = 'org.bluez.Device1'
AGENT = '/org/caelestia/PairingAgent'
AGENT_INTERFACE = Gio.DBusNodeInfo.new_for_xml("""
<node><interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="Cancel"/>
  <method name="RequestPinCode"><arg type="o"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o"/><arg type="s"/></method>
  <method name="RequestPasskey"><arg type="o"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o"/><arg type="u"/><arg type="q"/></method>
  <method name="RequestConfirmation"><arg type="o"/><arg type="u"/></method>
  <method name="RequestAuthorization"><arg type="o"/></method>
  <method name="AuthorizeService"><arg type="o"/><arg type="s"/></method>
</interface></node>
""").interfaces[0]


class PairingAgent:
    def __init__(self, owner, path, name):
        self.owner, self.path, self.name = owner, path, name
        self.dialog = None
        self.pending = None

    def close(self):
        if self.pending:
            self.pending.return_dbus_error('org.bluez.Error.Canceled', 'Pairing canceled')
            self.pending = None
        if self.dialog:
            self.dialog.destroy()
            self.dialog = None

    def handle(self, bus, sender, path, interface, method, parameters, request):
        args = parameters.unpack()
        if sender != self.owner or (args and args[0] != self.path):
            request.return_dbus_error('org.bluez.Error.Rejected', 'Unexpected pairing request')
            return
        self.close()
        if method in ('Cancel', 'Release', 'RequestAuthorization', 'AuthorizeService'):
            # Only the locally selected device can reach this agent.
            request.return_value(None)
            return
        try:
            self.prompt(method, args, request)
        except (ValueError, RuntimeError, ImportError) as error:
            request.return_dbus_error('org.bluez.Error.Rejected', str(error))

    def prompt(self, method, args, request):
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
        entry = None
        display = method in ('DisplayPasskey', 'DisplayPinCode')
        if display:
            code = f'{args[1]:06d}' if method == 'DisplayPasskey' else args[1]
            message = f'Enter {code} on {self.name}.'
        elif method == 'RequestConfirmation':
            message = f'Does {self.name} show {args[1]:06d}?'
        else:
            message = f'Enter the pairing code for {self.name}.'
            entry = Gtk.Entry(max_length=6 if method == 'RequestPasskey' else 16)
        dialog = Gtk.MessageDialog(text=message, buttons=Gtk.ButtonsType.CLOSE if display else Gtk.ButtonsType.OK_CANCEL)
        dialog.set_title('Bluetooth')
        if entry is not None:
            dialog.get_content_area().pack_start(entry, False, False, 0)
            entry.set_activates_default(True)
            dialog.set_default_response(Gtk.ResponseType.OK)
        if display:
            request.return_value(None)
        else:
            self.pending = request

        def respond(_, response):
            pending, self.pending = self.pending, None
            if pending:
                value = entry.get_text() if entry is not None else ''
                if response != Gtk.ResponseType.OK:
                    pending.return_dbus_error('org.bluez.Error.Rejected', 'Pairing declined')
                elif method == 'RequestPinCode' and value:
                    pending.return_value(GLib.Variant('(s)', (value,)))
                elif method == 'RequestPasskey' and value.isascii() and value.isdigit():
                    pending.return_value(GLib.Variant('(u)', (int(value),)))
                elif method == 'RequestConfirmation':
                    pending.return_value(None)
                else:
                    pending.return_dbus_error('org.bluez.Error.Rejected', 'Invalid pairing code')
            self.close()

        self.dialog = dialog
        dialog.connect('response', respond)
        dialog.show_all()


def pair_and_connect(bus, path):
    def proxy(interface, object_path):
        return Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, 'org.bluez', object_path, interface, None)

    device = proxy(DEVICE, path)
    paired = device.get_cached_property('Paired')
    if paired is None:
        raise ValueError('Device is no longer available')
    if not paired.unpack():
        manager = proxy('org.bluez.AgentManager1', '/org/bluez')
        agent = PairingAgent(manager.get_name_owner(), path, device.get_cached_property('Alias').unpack())
        registration = bus.register_object(AGENT, AGENT_INTERFACE, agent.handle, None, None)
        manager.RegisterAgent('(os)', AGENT, 'KeyboardDisplay')
        try:
            loop = GLib.MainLoop()
            result = []

            def finished(proxy, reply):
                result.append(reply)
                loop.quit()

            device.call('Pair', None, Gio.DBusCallFlags.NONE, 120000, None, finished)
            loop.run()
            device.call_finish(result[0])
        finally:
            agent.close()
            try:
                manager.UnregisterAgent('(o)', AGENT)
            finally:
                bus.unregister_object(registration)

        device.call_sync('org.freedesktop.DBus.Properties.Set',
                         GLib.Variant('(ssv)', (DEVICE, 'Trusted', GLib.Variant('b', True))),
                         Gio.DBusCallFlags.NONE, -1, None)
    try:
        device.Connect()
    except GLib.Error as error:
        if Gio.DBusError.get_remote_error(error) != 'org.bluez.Error.AlreadyConnected':
            raise


if __name__ == '__main__':
    try:
        pair_and_connect(Gio.bus_get_sync(Gio.BusType.SYSTEM, None), sys.argv[1])
    except (GLib.Error, ValueError) as error:
        if isinstance(error, GLib.Error):
            Gio.DBusError.strip_remote_error(error)
        sys.exit(error.message if isinstance(error, GLib.Error) else str(error))
