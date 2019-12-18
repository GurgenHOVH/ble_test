import 'package:ble_test/ble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';

main(List<String> args) async {
  // Init MyApp BLE
  await MyAppBLE().init();

  PermissionStatus permission =
      await PermissionHandler().checkPermissionStatus(PermissionGroup.location);

  if (permission != PermissionStatus.granted) {
     await PermissionHandler().requestPermissions([PermissionGroup.location]);
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BLETest(),
    );
  }
}

class BLETest extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _BleTestState();
  }
}

class _BleTestState extends State<BLETest> {
  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        RaisedButton(
          child: Text('Connect'),
          onPressed: () {
            connect();
          },
        ),
        RaisedButton(
          child: Text('Listen'),
          onPressed: () {
            listen();
          },
        ),
        RaisedButton(
          child: Text('Write'),
          onPressed: () {
            write();
          },
        ),
      ],
    ));
  }

  write() async {
    MyAppBLE myAppBLE = MyAppBLE();

    // Get data to write
    List<int> writeData = CommandData.getNetworkStatus();

    await myAppBLE.device.characteristicWrite(writeData);
  }

  listen() {
    MyAppBLE myAppBLE = MyAppBLE();

    myAppBLE.device.messageListener().listen((d) {
      print(d.map((i) => i.toString()).toList().join(','));
    });
  }

  Future<void> connect() async {
    MyAppBLE myAppBLE = MyAppBLE();

    var stream = await myAppBLE.device.startDeviceSearch();

    stream.listen((d) async {
      await myAppBLE.device.stopDeviceSearch();

      await myAppBLE.device.setActiveDevice(d);

      await myAppBLE.device.connect();

      print(myAppBLE.device.status.toString());

      if (myAppBLE.device.status != PeripheralConnectionState.connected) {
        await for (var state in myAppBLE.device.deviceConnectionState) {
          if (state == PeripheralConnectionState.connected) break;
        }
      }

      var services = await myAppBLE.device.discoverServices();

      var tfService = myAppBLE.device.myAppService(services);

      await myAppBLE.device.setActiveService(tfService);

      var chars = await myAppBLE.device.serviceCharacteristics();

      var tfChar = myAppBLE.device.myAppCharacteristic(chars);

      myAppBLE.device.setActiveCharacteristic(tfChar);
    });
  }
}

/// Helpers

class CommandData {
  static List<int> getNetworkStatus() {
    // Header
    int code = 0x24;
    int chunkInfo = 0x11;

    // Data to write
    List<int> data = commandDataList(code, [], chunkInfo);

    return data;
  }
}

List<int> commandDataList(int command, List<int> commandData, int chunkNumber) {
  // Reset the data for each iteration.
  List<int> data = [];

  // Payload of the command or message.
  List<int> payload = commandData;

  // Add the command code to header
  List<int> header = [
    // Command code
    command,
    // Payload chunking information.
    chunkNumber,
    // Size of the payload
    payload.length
  ];

  // Sum of header and payload
  int sum = sumByteLists(header, payload);

  // The two's complement of the sum.
  int checksum = twosComplement(sum);

  // Collect the data to send to BLE.
  data
    ..addAll(header)
    ..addAll(payload)
    ..add(checksum);

  return data;
}

/// Returns the sum of bytes of two lists
int sumByteLists(List<int> one, List<int> other) {
  List<int> all = [];
  all..addAll(one)..addAll(other);

  return all.reduce((a, b) => a + b);
}

/// Returns the two's complement.
int twosComplement(int number) {
  return (~(number) + 1) & 0xFF;
}
