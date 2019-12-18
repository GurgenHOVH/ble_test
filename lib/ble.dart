import 'dart:io';

import 'package:ble_test/device.dart';


// import 'package:flutter_blue/flutter_blue.dart';
import 'dart:async';
// export 'package:flutter_blue/flutter_blue.dart' show BluetoothDeviceState;

import 'package:flutter_ble_lib/flutter_ble_lib.dart';

/// Main class for interaction with BLE interface.
///
///
class MyAppBLE {
  /// Holds the single instance of `MyAppBLE` class
  static MyAppBLE _singleton;

  // Init Flutter BLE module
  BleManager _bleManager = BleManager();

  /// Contains Device specific actions(discover/connect)
  Device device;

  // /// Bluetooth current State.
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  // /// Returns the current bluetooth state.
  // BluetoothState get bluetoothState => _bluetoothState;

  Stream<BluetoothState> bluetoothStateStream;

  /// Whatever bluetooth is on or not.
  bool isBluetoothOn = false;

  /// Factory constructor to return single instance of
  /// `MyAppBLE` class for application lifetime.
  factory MyAppBLE() {
    if (_singleton == null) {
      _singleton = MyAppBLE._internal();
    }

    return _singleton;
  }

  Future<void> init() async {
    await _bleManager.createClient();

    _bluetoothState = await _bleManager.bluetoothState();

    bluetoothStateStream =
        _bleManager.observeBluetoothState().asBroadcastStream();

    // Subscribe to state changes
    _bleManager.observeBluetoothState().listen((state) {
      _bluetoothState = state;

      switch (state) {
        case BluetoothState.POWERED_ON:
          isBluetoothOn = true;
          break;
        default:
          isBluetoothOn = false;
      }
    });

    isBluetoothOn = _bluetoothState == BluetoothState.POWERED_ON;

    if (!isBluetoothOn) {
      // Enable the bluetooth if on Android
      if (Platform.isAndroid) {
        await _bleManager.enableRadio();
      } else {
        //#TODO: Implement for iOS
      }
    }

    // Init device specific commands.
    device = Device(_bleManager);
  }

  Future<void> enableBt() async {
    await _bleManager.enableRadio();
  }

  /// Private Internal constuctor. Used only by factory constructor.
  MyAppBLE._internal();
}
