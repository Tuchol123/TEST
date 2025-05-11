import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';

class DataScreen extends StatefulWidget {
  final BluetoothDevice? connectedDevice;

  const DataScreen({Key? key, required this.connectedDevice, BluetoothCharacteristic? txCharacteristic}) : super(key: key);

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool isStarted = false;
  int batteryLevel = 0;
  double currentConsumption = 0.0; // Ampery
  double distanceTraveled = 0.0;   // Metry

  BluetoothCharacteristic? txChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription<List<int>>? notifySubscription;

  List<List<String>> dataLog = []; // do CSV

  @override
  void initState() {
    super.initState();
    if (widget.connectedDevice != null) {
      _listenToBluetoothData();
    }
  }

  @override
  void dispose() {
    notifySubscription?.cancel();
    super.dispose();
  }

Future<void> _sendCommand(String command) async {
  if (txChar != null) {
    try {
      await txChar!.write("$command\r\n".codeUnits, withoutResponse: true);
      print("📤 Wysłano komendę: $command");
    } catch (e) {
      print("❌ Błąd podczas wysyłania komendy $command: $e");
    }
  } else {
    print("⚠️ txChar jest null – nie można wysłać komendy $command");
  }
}

Future<void> _listenToBluetoothData() async {
  List<BluetoothService> services = await widget.connectedDevice!.discoverServices();
  for (BluetoothService service in services) {
    for (BluetoothCharacteristic characteristic in service.characteristics) {
      // Nasłuch danych
      if (characteristic.properties.notify) {
        await characteristic.setNotifyValue(true);
        notifyChar = characteristic;

        // Jeśli notifyChar również pozwala na zapis, ustaw jako txChar
        if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
          txChar = characteristic;
          print("✅ txChar ustawiony (na podstawie notify): ${txChar!.uuid}");
        }

        notifySubscription = characteristic.onValueReceived.listen((value) {
          final text = String.fromCharCodes(value);
          _parseIncomingData(text);
        });
      }

      // Alternatywnie: ustaw txChar jeśli jeszcze nie ustawiony
      if (txChar == null && (characteristic.properties.write || characteristic.properties.writeWithoutResponse)) {
        txChar = characteristic;
        print("✅ txChar ustawiony (alternatywa): ${txChar!.uuid}");
      }
    }
  }

  if (txChar == null) {
    print("⚠️ Nie znaleziono charakterystyki do wysyłania danych (write)");
  }
}

  void _parseIncomingData(String input) {
    // Oczekiwany format np.: START,80,45,120\n
    final parts = input.trim().split(',');

    if (parts.length >= 4) {
      setState(() {
        isStarted = parts[0] == "START";
        batteryLevel = int.tryParse(parts[1]) ?? 0;
        currentConsumption = (int.tryParse(parts[2]) ?? 0) / 1000.0; // mA → A
        distanceTraveled = double.tryParse(parts[3]) ?? 0.0;
      });

      // Zapis do logu CSV
      dataLog.add([
        DateTime.now().toIso8601String(),
        isStarted ? "START" : "STOP",
        batteryLevel.toString(),
        (currentConsumption * 1000).toStringAsFixed(0), // w mA
        distanceTraveled.toStringAsFixed(2)
      ]);
    }
  }

 void _resetData() {
    setState(() {
      isStarted = false;
      // batteryLevel = 0; // Zazwyczaj poziom baterii nie jest resetowany przez użytkownika
      currentConsumption = 0.0;
      distanceTraveled = 0.0;
      dataLog.clear(); // <--- KLUCZOWA ZMIANA: Czyszczenie logu CSV
    });
      print("🔄 Dane zresetowane. Log CSV wyczyszczony.");
  }

  Future<void> _saveDataToCSV() async {
    final directory = await getDownloadsDirectory();
    final file = File("${directory?.path}/telemetry_${DateTime.now().millisecondsSinceEpoch}.csv");

    final buffer = StringBuffer();
    buffer.writeln("Czas,Status,Bateria (%),Prąd (mA),Dystans (m)");

    for (var row in dataLog) {
      buffer.writeln(row.join(','));
    }

    await file.writeAsString(buffer.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Dane zapisane do pliku: ${file.path}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Expanded(child: _dataItem(isStarted ? 'STARTED' : 'STOPPED', flex: 1)),
              const SizedBox(height: 15),
              Expanded(child: _dataItem('$batteryLevel%', isBattery: true, flex: 1)),
              const SizedBox(height: 15),
              Expanded(child: _dataItem('${(currentConsumption * 1000).toStringAsFixed(0)} mA', flex: 1)),
              const SizedBox(height: 15),
              Expanded(child: _dataItem('${distanceTraveled.toStringAsFixed(0)} m', flex: 1)),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                      _resetData(); // lokalny reset
                      _sendCommand("RESET");
                    },
                      child: const Text("RESET", style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveDataToCSV,
                      child: const Text("SAVE", style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataItem(String value, {bool isBattery = false, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.all(15.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Center(
          child: isBattery
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.battery_full, color: Colors.green, size: 36),
                    const SizedBox(width: 12),
                    Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                  ],
                )
              : Text(value, style: const TextStyle(fontSize: 36)),
        ),
      ),
    );
  }
}
