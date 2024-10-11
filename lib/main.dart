import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    print("Erreur lors du chargement du fichier .env : $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Évaluation de Santé des Plantes',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: const MyHomePage(title: 'Évaluez la santé de votre plante'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  String _result = "";
  String _plantName = ""; // Nom de la plante identifiée
  String _healthStatus = '';
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = "";
        _healthStatus = '';
        _plantName = '';
      });
    }
  }

  Future<void> _sendImageToAPI() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _result = "";
      _healthStatus = '';
      _plantName = '';
    });

    try {
      List<int> imageBytes = await _image!.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      // Préparez les données de la requête comme dans le code Python
      Map<String, dynamic> data = {
        'images': ['data:image/jpeg;base64,$base64Image'],
        'latitude': 49.207,
        'longitude': 16.608,
        'similar_images': true,
      };

      var response = await http.post(
        Uri.parse('https://plant.id/api/v3/health_assessment'),
        headers: {
          'Content-Type': 'application/json',
          'Api-Key': dotenv.env['PLANT_ID_API_KEY'] ?? '',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        var decodedData = json.decode(response.body);
        _processApiResponse(decodedData);
      } else {
        setState(() {
          _result = "Échec de l'analyse. Code ${response.statusCode}";
          print("Erreur: ${response.statusCode}, Réponse: ${response.body}");
        });
      }
    } catch (e) {
      setState(() {
        _result = "Erreur lors de l'envoi : $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _processApiResponse(Map<String, dynamic> data) {
    setState(() {
      // Identification de la plante retirée, analyse directe de l'état de santé
      bool isHealthy = data['result']['is_healthy']['binary'];
      double healthProbability =
          data['result']['is_healthy']['probability'] * 100;

      if (isHealthy) {
        _healthStatus =
            'La plante est en bonne santé (Probabilité : ${healthProbability.toStringAsFixed(2)}%)';
      } else {
        _healthStatus =
            'La plante présente des problèmes de santé (Probabilité : ${healthProbability.toStringAsFixed(2)}%).';

        if (data['result']['disease'] != null &&
            data['result']['disease']['suggestions'] != null) {
          var diseaseSuggestions = data['result']['disease']['suggestions'];
          StringBuffer suggestionsBuffer = StringBuffer();
          for (var suggestion in diseaseSuggestions) {
            suggestionsBuffer.writeln(
                '${suggestion['name']} avec une probabilité de ${(suggestion['probability'] * 100).toStringAsFixed(2)}%');
          }
          _healthStatus +=
              '\nProblèmes suggérés :\n' + suggestionsBuffer.toString();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_image != null)
                  Image.file(_image!, height: 200)
                else
                  const Text('Aucune image sélectionnée'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.image),
                      label: const Text('Galerie'),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Caméra'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_image != null)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _sendImageToAPI,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Analyser'),
                  ),
                const SizedBox(height: 20),
                Text(
                  _result,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  _healthStatus,
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
