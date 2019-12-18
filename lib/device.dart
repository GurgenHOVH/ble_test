import 'dart:typed_data';



import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';

const _devicePrefix = 'tf';
const _serviceUUID = '8ba16c631810c6d21a3d09eb265d0000';
const _characteristicUUID = '8ba16c631810c6d21a3d09eb265d0001';

/// Responsible for discovering and connecting MyApp BLE device.
/// ### Device Name
/// The peripheral advertises its BLE API interface with the following format:
/// `myApp-<UUID>` where is the peripheral hardware string representation of
///  the 12-bytes unique device identifier.
/// ### MyApp Service
/// The only advertised service is named `MyApp Service` and its UUID
///  is `8ba16c631810c6d21a3d09eb265d0000`.
/// ### `Control` Characteristic
/// The `MyApp Service` is offering an unique characteristic which has
/// a BLE descriptor whose name is `Control` . The UUID of the Control
/// characteristic is `8ba16c631810c6d21a3d09eb265d0001` .
/// The Control characteristic supports the following operations:
/// - `Read`
/// - `Write`
/// - `Notification`
class Device {
  /// The instance of FlutterBlue module.
  final BleManager _bleManager;


  /// Stream of MyApp BLE devices.
  final myAppDevices = PublishSubject<Peripheral>();

  /// Discovered device names
  final List<String> _deviceNames = [];

  Device(this._bleManager);

  /// Stream of BLE device scan results.
  StreamSubscription<ScanResult> _scanSubscription;
  StreamSubscription<PeripheralConnectionState> _deviceConnection;

  /// peripheral device Bluetooth connection status.
  PeripheralConnectionState _status = PeripheralConnectionState.disconnected;
  PeripheralConnectionState get status => _status;

  /// Selected and active BLE device.
  Peripheral _activeDevice;
  Peripheral get activeDevice => _activeDevice;

  /// Selected and active BLE service.
  Service _activeService;
  Service get activeService => _activeService;

  /// Active BluetoothCharacteristic
  Characteristic _activeCharacteristic;
  Characteristic get activeCharacteristic => _activeCharacteristic;

  Stream<Uint8List> characteristicsData;

  List<Map<int, Uint8List>> _bleWriteDataQueue = [];

  // Empty stream for cases when the device is not connected
  Stream<Uint8List> emptyStream;

  /// Starts discovering BLE devices.
  /// Returns a Stream of myApp-<UUID> devices.
  /// The function continues discovering BLE devices
  ///  untill reaching the timeout, or when the user
  ///  stops device search by calling stopDeviceSearch().
  Future<Observable<Peripheral>> startDeviceSearch() async {
    _bleManager.setLogLevel(LogLevel.verbose);
    // Delete the last search results
    _deviceNames.removeWhere((_) => true);

    await _bleManager.stopPeripheralScan();

    // Start scanning
    _bleManager.startPeripheralScan().listen((scanResult) {
      String deviceid = scanResult.peripheral.identifier;
      String deviceName = scanResult.advertisementData.localName;

      print('========' + (scanResult.advertisementData.localName ?? 'No Name'));

      print(scanResult.advertisementData.serviceUUIDs.toString());

      // We are looking for only MyApp devices, which have
      // specific name format.
      if (deviceName != null &&
          deviceName.contains(_devicePrefix) &&
          !_deviceNames.contains(deviceid)) {
        // if (!_deviceNames.contains(deviceName)) {
        // Save the device name to do not have duplicate devices in stream.
        _deviceNames.add(deviceid);

        // Add the device to the stream of MyApp devices.
        myAppDevices.sink.add(scanResult.peripheral);
      }
    });

    // Return a stream of BluetoothDevice objects.
    return myAppDevices;
  }

  /// Stops the scaning for BLE devices
  Future<void> stopDeviceSearch() async {
    await _bleManager.stopPeripheralScan();
  }

  /// Sets the active MyApp device. Must be called
  ///  before `connect`.
  Future<void> setActiveDevice(Peripheral device) async {
    print('Set active device =============' + device.name ?? '');
    _activeDevice = device;

    // Update the connection state immediately
    deviceConnectionState.listen((newState) {
      _status = newState;

      if (_status == PeripheralConnectionState.disconnected &&
          _status != PeripheralConnectionState.connecting &&
          activeCharacteristic != null) {
        print('========Reconnecting');
        Future.delayed(Duration(seconds: 1), () {
          connect();
        });
      }
    });
  }

  /// Connects to MyApp BLE device. Must be called
  /// after `setActiveDevice`.
  /// Returns a Stream with `BluetoothDeviceState`, so
  /// the connection progress and result can be tracked.
  Future<StreamSubscription<PeripheralConnectionState>> connect() async {
    // throw an exeption if connect is called before seting active device.
    if (activeDevice == null) {
      throw Exception("No active device found. Call setActiveDevice() first");
    }

    // Check if already connected
    bool connected = await activeDevice.isConnected();

    if (!connected) {
      try {
        activeDevice.connect(
          isAutoConnect: false,
          timeout: Duration(seconds: 10),
        );
      } catch (e) {
        // Close the subscription when done.
        _deviceConnection?.cancel();
      }
    }

    // Connect to device
    _deviceConnection = deviceConnectionState.listen(
      (connectionStatus) {
        // Update the status
        _status = connectionStatus;
      },
      onDone: () {
        // Close the subscription when done.
        _deviceConnection?.cancel();
      },
    );

    return _deviceConnection;
  }

  Stream<PeripheralConnectionState> get deviceConnectionState {
    if (activeDevice == null) {
      throw Exception("Active Device is null");
    }

    return activeDevice
        .observeConnectionState(emitCurrentValue: true)
        .asBroadcastStream();
  }

  /// Finds and returns the list of available services.
  /// To set the active service call setActiveService().
  Future<List<Service>> discoverServices() async {
    // throw an exeption if connect is called before seting active device.
    if (activeDevice == null || status != PeripheralConnectionState.connected) {
      throw Exception(
          "No active device found. Call setActiveDevice() and connect() first");
    }

    // Get the device services.
    await activeDevice.discoverAllServicesAndCharacteristics();
    List<Service> services = await activeDevice.services();

    return services;
  }

  /// Returns the myApp service from the given services list.
  Service myAppService(List<Service> services) {
    // uuid:"8ba16c63-1810-c6d2-1a3d-09eb265d0000"

    return services
        .singleWhere((service) => service.uuid == formatAsUUID(_serviceUUID));
  }

  String formatAsUUID(String input) {
    input = input.replaceAll("-", "");
    // 8ba16c63-1810-c6d2-1a3d-09eb265d0000
    return input.substring(0, 8) +
        '-' +
        input.substring(8, 12) +
        '-' +
        input.substring(12, 16) +
        '-' +
        input.substring(16, 20) +
        '-' +
        input.substring(20, 32);
  }

  /// Sets the active service. All the READ/WRITE operations
  ///  will be done on this service.
  Future<void> setActiveService(Service service) async {
    // Set the active service
    _activeService = service;

    // Set the active characteristic
    _activeCharacteristic = (await service.characteristics()).singleWhere(
        (characteristic) =>
            characteristic.uuid == formatAsUUID(_characteristicUUID));
  }

  /// Returns the list of BluetoothCharacteristics for active service.
  Future<List<Characteristic>> serviceCharacteristics() async {
    return activeService.characteristics();
  }

  /// Returns the myApp Characteristic from the given characteristics list.
  Characteristic myAppCharacteristic(List<Characteristic> characteristics) {
    return characteristics.singleWhere((characteristic) =>
        characteristic.uuid == formatAsUUID(_characteristicUUID));
  }

  /// Sets the active characteristic. All the READ/WRITE operations
  ///  will be done on this characteristic.
  void setActiveCharacteristic(Characteristic characteristic) {
    // Set the active characteristic
    _activeCharacteristic = characteristic;

    messageListener().listen((data) {
      logDataFromCentral(data);
    });
  }

  /// Reads and returns the value of active characteristic.
  Future<List<int>> characteristicRead() async {
    List<int> value = await activeCharacteristic.read();

    return value;
  }

  /// Writes the value of an active characteristic.
  Future<void> characteristicWrite(List<int> value,
      {String transactionId}) async {
    if (status != PeripheralConnectionState.connected) {
      throw Exception("Device is not connected. Connection status = $status");
    }

    print('Data Write Start');

    await Future.delayed(Duration(milliseconds: 500));

    if (_bleWriteDataQueue.length > 0) {
      print('Data Write Queue: ${_bleWriteDataQueue.length}');
    }

    _bleWriteDataQueue.add({value.hashCode: Uint8List.fromList(value)});

    await activeCharacteristic.write(Uint8List.fromList(value), false);

    _bleWriteDataQueue.removeWhere((q) => q.keys.first == value.hashCode);

    print('Data Write done');

    // await _bleManager.cancelTransaction(value.hashCode.toString());

    logDataFromClient(Uint8List.fromList(value));
  }

  logDataFromClient(Uint8List data) {
    // BleLogger().log(1, data.first, data);
  }

  logDataFromCentral(Uint8List data) {
    // BleLogger().log(0, data.first, data);
  }

  /// Listen to changes of this stream to be notified when
  ///  the active characteristic's value is changed.
  Future<Stream<List<int>>> changeListener() async {
    // Enable change notifications
    // await activeCharacteristic. = true;

    // Return the stream from active device with active characteristic
    return activeCharacteristic.monitor();
  }

  /// Listen to changes of this stream to be notified when
  ///  the active characteristic's value is changed.
  Stream<Uint8List> messageListener() {
    // Enable change notifications
    if (characteristicsData == null &&
        status == PeripheralConnectionState.connected) {
      characteristicsData = activeCharacteristic.monitor().asBroadcastStream();
    }

    // Return the stream from active device with active characteristic
    return characteristicsData;
  }
}
