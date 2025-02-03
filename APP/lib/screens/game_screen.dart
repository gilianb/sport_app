import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.id,
    required this.remainTime,
    required this.device,
  });

  final String? id;
  final Duration remainTime;
  final BluetoothDevice? device;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> {
  late Duration _remainingTime;
  Timer? _timer;
  bool _waitingForESP = false;
  List<List<int>> receivedData = []; // Stocke les 10 valeurs reçues

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.remainTime;
    _startCountdown();
  }

  void _addPerformance(int time) async {
    // Récupérer la date d'aujourd'hui sous format YYYY-MM-DD
    String todayDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    // Créer l'objet performance avec la date et le temps reçus
    final performance = {
      'date': todayDate,
      'time': time,
    };

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(widget.id);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      await userRef.update({
        'performanceHistory': FieldValue.arrayUnion([performance]),
      });
    } else {
      await userRef.set({
        'performanceHistory': [performance],
      });
    }
  }

  /// Démarre le compte à rebours
  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime.inSeconds <= 0) {
        setState(() {
          _timer?.cancel();
          _waitingForESP = true;
        });
        _waitForESP();
      } else {
        setState(() {
          _remainingTime -= const Duration(seconds: 1);
        });
      }
    });
  }

  /// Écoute les données envoyées par l'ESP
  Future<void> readFromESP() async {
    if (widget.device == null) {
      print("Aucun appareil connecté !");
      return;
    }

    List<BluetoothService> services = await widget.device!.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.characteristicUuid ==
            Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8")) {
          if (characteristic.properties.notify) {
            // S'assurer qu'on active les notifications une seule fois
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((data) async {
              if (data.isNotEmpty && receivedData.length < 5) {
                print('Données reçues : $data');
                //setState(() {
                receivedData.add(data);
                //});
                print('Données stockées : $receivedData');
              }
              // Vérification de la condition pour arrêter la réception et naviguer
              if (receivedData.length >= 5) {
                print('Réception terminée, arrêt de la notification');
                await characteristic
                    .setNotifyValue(false); // Arrêter après 5 réceptions
                print('Notification arrêtée');
                if (_waitingForESP) {
                  setState(() {
                    _waitingForESP = false;
                  });
                  print('Données reçues : $receivedData');
                }
              }
            });
          }
        }
      }
    }
  }

  Future<void> _waitForESP() async {
    await readFromESP();

    // Vérification explicite du nombre de données avant de naviguer
    if (receivedData.length >= 5) {
      print("Données final reçues : $receivedData");
    } else {
      print("Erreur : Données insuffisantes");
    }
  }

  void end_game() {
    int time = receivedData.last.first - receivedData.first.first;
    _addPerformance(time);
    Navigator.pop(context);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Game Screen"),
        backgroundColor: const Color.fromARGB(255, 15, 91, 124),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/running_track.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: _waitingForESP
              ? const Text(
                  "Waiting for ESP messages...",
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Time Remaining",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _formatDuration(_remainingTime),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(height: 40), // Espacement avant le bouton
                    ElevatedButton(
                      onPressed: () {
                        end_game();
                        // Redirige vers l'écran principal
                      },
                      style: ElevatedButton.styleFrom(
                        iconColor: Colors.blue, // Couleur du bouton
                      ),
                      child: const Text(
                        'Fin du jeu',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }
}
