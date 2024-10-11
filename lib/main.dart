import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: "assets/.env");
  runApp(const MyApp());
}

Future<http.Client> getHttpClient() async {
  final ioc = HttpClient()
    ..badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
  return IOClient(ioc);
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Évaluation de Santé des Plantes',
      theme: ThemeData(primarySwatch: Colors.green),
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
  String _healthStatus = '';
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _result = "";
        _healthStatus = '';
      });
    }
  }

  Future<void> _sendImageToAPI() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _result = "";
      _healthStatus = '';
    });

    try {
      List<int> imageBytes = await _image!.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      Map<String, dynamic> data = {
        'images': ['data:image/jpeg;base64,$base64Image'],
        'latitude': 49.207,
        'longitude': 16.608,
        'similar_images': true,
      };

      var client = await getHttpClient();
      var response = await client.post(
        Uri.parse('https://plant.id/api/v3/health_assessment'),
        headers: {
          'Content-Type': 'application/json',
          'Api-Key': dotenv.env['PLANT_ID_API_KEY'] ?? '',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        var decodedData = json.decode(response.body);
        await _processApiResponse(decodedData);
      } else {
        setState(() {
          _result = "Échec de l'analyse. Code ${response.statusCode}";
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

  Future<void> _processApiResponse(Map<String, dynamic> data) async {
    bool isHealthy = data['result']['is_healthy']['binary'];
    double healthProbability =
        data['result']['is_healthy']['probability'] * 100;

    setState(() {
      _healthStatus = isHealthy
          ? 'La plante est en bonne santé (Probabilité : ${healthProbability.toStringAsFixed(2)}%)'
          : 'La plante présente des problèmes de santé (Probabilité : ${healthProbability.toStringAsFixed(2)}%).';
    });

    if (data['result']['disease'] != null &&
        data['result']['disease']['suggestions'] != null) {
      var diseaseSuggestions = data['result']['disease']['suggestions'];
      List<String> diseaseNames = diseaseSuggestions
          .map<String>((suggestion) => suggestion['name'].toString())
          .toList();

      try {
        Map<String, String> translations =
            await translateDiseaseNames(diseaseNames);
        _updateDiseaseStatus(diseaseSuggestions, translations);
      } catch (e) {
        print('Erreur lors de la traduction : $e');
        _updateDiseaseStatus(diseaseSuggestions, {});
      }
    }
  }

  Future<Map<String, String>> translateDiseaseNames(
      List<String> diseaseNames) async {
    try {
      final client = await getHttpClient();
      final url = Uri.parse('https://urbano.pythonanywhere.com/translate/');

      print('Envoi de la requête à : $url');
      print('Noms de maladies à traduire : $diseaseNames');

      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'disease_names': diseaseNames}),
      );

      print('Code de statut de la réponse : ${response.statusCode}');
      print('Corps de la réponse : ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['translations'] != null) {
          return Map<String, String>.from(data['translations']);
        } else {
          throw Exception(
              'La clé "translations" est manquante dans la réponse.');
        }
      } else {
        throw Exception(
            'Erreur de l\'API de traduction : ${response.statusCode}');
      }
    } catch (e) {
      print('Exception lors de la traduction : $e');
      rethrow;
    }
  }

  void _updateDiseaseStatus(
      List<dynamic> suggestions, Map<String, String> translations) {
    StringBuffer suggestionsBuffer = StringBuffer();
    for (var suggestion in suggestions) {
      String englishName = suggestion['name'].toString();
      String displayName = translations[englishName] ?? englishName;
      suggestionsBuffer.writeln(
          '$displayName avec une probabilité de ${(suggestion['probability'] * 100).toStringAsFixed(2)}%');
    }

    setState(() {
      _healthStatus +=
          '\n\nProblèmes suggérés :\n' + suggestionsBuffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
