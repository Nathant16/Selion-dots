pragma Singleton
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking

Item {
    id: root

    function _hasWifiDevice() {
        if (typeof Networking === "undefined" || !Networking || !Networking.devices) return false;
        let devs = Networking.devices.values || Networking.devices;
        let count = devs.length !== undefined ? devs.length : (devs.count !== undefined ? devs.count : 0);
        for (let i = 0; i < count; i++) {
            let d = devs[i] !== undefined ? devs[i] : (devs.get ? devs.get(i) : null);
            if (d && d.type === DeviceType.Wifi) return true;
        }
        return false;
    }

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property bool _bluetoothEnabled: Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
    readonly property bool bluetoothEnabled: _bluetoothEnabled
    readonly property bool hasRadios: _hasWifiDevice() || Boolean(Bluetooth.defaultAdapter)
    readonly property bool airplaneMode: hasRadios && (!_hasWifiDevice() || !wifiEnabled) && (!Bluetooth.defaultAdapter || !bluetoothEnabled)

    property bool wifiBeforeAirplane: true
    property bool btBeforeAirplane: true

    function _syncBluetooth() {
        root._bluetoothEnabled = Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled);
    }

    function setWifiEnabled(enabled) {
        if (!_hasWifiDevice()) return;
        Networking.wifiEnabled = Boolean(enabled);
    }

    function setBluetoothEnabled(enabled) {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = Boolean(enabled);
        }
    }

    function setAirplaneMode(enabled) {
        let target = Boolean(enabled);
        let hasWifi = root._hasWifiDevice();
        let hasBt = Boolean(Bluetooth.defaultAdapter);
        if (!hasWifi && !hasBt) return;
        if (target) {
            if (root.wifiEnabled || root.bluetoothEnabled) {
                root.wifiBeforeAirplane = root.wifiEnabled;
                root.btBeforeAirplane = root.bluetoothEnabled;
            } else {
                root.wifiBeforeAirplane = hasWifi;
                root.btBeforeAirplane = hasBt;
            }
            if (hasWifi) root.setWifiEnabled(false);
            if (hasBt) root.setBluetoothEnabled(false);
        } else {
            let restoreWifi = hasWifi && root.wifiBeforeAirplane;
            let restoreBt = hasBt && root.btBeforeAirplane;
            if (!restoreWifi && !restoreBt) {
                restoreWifi = hasWifi;
                restoreBt = hasBt;
            }
            if (hasWifi) root.setWifiEnabled(restoreWifi);
            if (hasBt) root.setBluetoothEnabled(restoreBt);
        }
    }

    function toggleAirplaneMode() {
        root.setAirplaneMode(!root.airplaneMode);
    }

    Connections {
        target: Bluetooth
        ignoreUnknownSignals: true
        function onDefaultAdapterChanged() {
            root._syncBluetooth();
        }
    }

    Connections {
        target: Bluetooth.defaultAdapter || null
        ignoreUnknownSignals: true
        function onEnabledChanged() {
            root._syncBluetooth();
        }
    }
}
