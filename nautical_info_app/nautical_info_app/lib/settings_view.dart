import 'package:flutter/material.dart';

class SettingsView extends StatefulWidget {
  final String currentBuoyStation;
  final String currentTideStation;

  const SettingsView({
    super.key,
    required this.currentBuoyStation,
    required this.currentTideStation,
  });

  @override
  _SettingsViewState createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _buoyController;
  late TextEditingController _tideController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _buoyController = TextEditingController(text: widget.currentBuoyStation);
    _tideController = TextEditingController(text: widget.currentTideStation);
  }

  @override
  void dispose() {
    _buoyController.dispose();
    _tideController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    if (_formKey.currentState!.validate()) {
      final newStations = {
        'buoyStation': _buoyController.text,
        'tideStation': _tideController.text,
      };
      Navigator.pop(context, newStations);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _buoyController,
                decoration: const InputDecoration(
                  labelText: 'Buoy Station ID',
                  hintText: 'e.g., 44013',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a buoy station ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _tideController,
                decoration: const InputDecoration(
                  labelText: 'Tide Station ID',
                  hintText: 'e.g., 8443970',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a tide station ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Save and Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
