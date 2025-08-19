import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

// MARK: - Main App Initialization
void main() {
  runApp(const BuoyApp());
}

class BuoyApp extends StatelessWidget {
  const BuoyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use ChangeNotifierProvider to manage the app's state.
    return ChangeNotifierProvider(
      create: (_) => BuoyViewModel(),
      child: MaterialApp(
        title: 'NOAA Buoy Data',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        ),
        home: const ContentView(),
      ),
    );
  }
}

// MARK: - Data Models
// These classes model the data from the NOAA APIs.

class TidePrediction {
  final String t; // Time of the prediction
  final String v; // Water level
  final String type; // "H" for high tide, "L" for low tide

  TidePrediction({required this.t, required this.v, required this.type});

  // **FIXED**: This factory now checks for null values from the API
  // before assigning them to prevent the TypeError.
  factory TidePrediction.fromJson(Map<String, dynamic> json) {
    return TidePrediction(
      t: json['t'] as String? ?? '', // Use ?? '' to provide a default empty string if null
      v: json['v'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }
}

// New model for the parsed text data from the NDBC buoy feed.
class BuoyObservation {
  final DateTime time;
  final double? waveHeight; // WVHT in meters
  final double? airTemp; // ATMP in Celsius

  BuoyObservation({required this.time, this.waveHeight, this.airTemp});

  // Computed properties for unit conversion.
  double? get waveHeightInFeet => waveHeight != null ? waveHeight! * 3.28084 : null;
  double? get airTempInFahrenheit => airTemp != null ? (airTemp! * 9/5) + 32 : null;
}


// MARK: - Networking Service
// This class handles all communication with the NOAA APIs.

class NOAAService {
  // Fetches tide predictions for a given station (remains the same).
  Future<List<TidePrediction>> fetchTideData(String station) async {
    final urlString = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?date=today&station=$station&product=predictions&datum=MLLW&time_zone=lst_ldt&units=english&format=json";
    final response = await http.get(Uri.parse(urlString));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List predictionsJson = data['predictions'];
      return predictionsJson.map((p) => TidePrediction.fromJson(p)).toList();
    } else {
      throw Exception('Failed to load tide data');
    }
  }

  // New method to fetch and parse real-time buoy data from the text file.
  Future<List<BuoyObservation>> fetchBuoyData(String station) async {
    final url = Uri.parse('https://www.ndbc.noaa.gov/data/realtime2/$station.txt');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return _parseBuoyData(response.body);
    } else {
      throw Exception('Failed to load buoy data for station: $station');
    }
  }

  // Private helper to parse the space-delimited text file.
  List<BuoyObservation> _parseBuoyData(String data) {
    final lines = data.split('\n');
    if (lines.length < 3) {
      // Not enough data to parse.
      return [];
    }

    // The first line contains the headers, prefixed with '#'.
    final headerLine = lines[0];
    final headers = headerLine.replaceAll('#', '').trim().split(RegExp(r'\s+'));

    // Find the column index for the data we care about.
    final colIndices = {
      'YY': headers.indexOf('YY'),
      'MM': headers.indexOf('MM'),
      'DD': headers.indexOf('DD'),
      'hh': headers.indexOf('hh'),
      'mm': headers.indexOf('mm'),
      'WVHT': headers.indexOf('WVHT'), // Wave Height
      'ATMP': headers.indexOf('ATMP'), // Air Temperature
    };

    // Check if all required headers are present.
    if (colIndices.values.any((i) => i == -1)) {
        throw Exception('A required column (e.g., YY, WVHT, ATMP) was not found in the buoy data file.');
    }

    final observations = <BuoyObservation>[];
    // Start from the third line (index 2) to skip headers and units.
    for (int i = 2; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;

      final values = line.split(RegExp(r'\s+'));
      if (values.length < headers.length) continue; // Skip malformed lines.

      try {
        // Construct the observation time.
        final year = int.parse(values[colIndices['YY']!]);
        final month = int.parse(values[colIndices['MM']!]);
        final day = int.parse(values[colIndices['DD']!]);
        final hour = int.parse(values[colIndices['hh']!]);
        final minute = int.parse(values[colIndices['mm']!]);
        final time = DateTime.utc(year, month, day, hour, minute);

        // Parse values, handling "MM" for missing data.
        final waveHeight = double.tryParse(values[colIndices['WVHT']!]);
        final airTemp = double.tryParse(values[colIndices['ATMP']!]);
        
        observations.add(BuoyObservation(
          time: time,
          waveHeight: waveHeight,
          airTemp: airTemp,
        ));
      } catch (e) {
        // Log or handle parsing errors for a specific line.
        debugPrint('Skipping malformed line: $line, Error: $e');
      }
    }
    return observations;
  }
}

// MARK: - View Model (State Management)
// This class uses ChangeNotifier to notify widgets of state changes.

class BuoyViewModel extends ChangeNotifier {
  List<TidePrediction> _tidePredictions = [];
  List<BuoyObservation> _buoyObservations = []; // Changed to the new model.
  bool _isLoading = false;
  String? _errorMessage;

  // Public getters for the private state variables.
  List<TidePrediction> get tidePredictions => _tidePredictions;
  List<BuoyObservation> get buoyObservations => _buoyObservations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Getter for the most recent observation.
  BuoyObservation? get latestObservation => _buoyObservations.isNotEmpty ? _buoyObservations.first : null;

  // Station IDs
  final String _buoyStation = "44013"; // Boston Buoy
  final String _tideStation = "8443970"; // Boston Harbor
  final NOAAService _noaaService = NOAAService();

  BuoyViewModel() {
    fetchData();
  }

  Future<void> fetchData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Use Future.wait to run all API calls concurrently.
      final results = await Future.wait([
        _noaaService.fetchTideData(_tideStation),
        _noaaService.fetchBuoyData(_buoyStation), // Updated call.
      ]);
      
      _tidePredictions = results[0] as List<TidePrediction>;
      _buoyObservations = results[1] as List<BuoyObservation>;

    } catch (e) {
      _errorMessage = "Failed to fetch data. Please check your connection. Error: ${e.toString()}";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}


// MARK: - Flutter Widgets (UI)

class ContentView extends StatelessWidget {
  const ContentView({super.key});

  @override
  Widget build(BuildContext context) {
    // Consumer widget listens to changes in BuoyViewModel and rebuilds the UI.
    return Scaffold(
      appBar: AppBar(
        title: const Text("Boston Buoy (44013)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<BuoyViewModel>().fetchData();
            },
          ),
        ],
      ),
      body: Consumer<BuoyViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading && viewModel.buoyObservations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (viewModel.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(viewModel.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: viewModel.fetchData,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                CurrentWaveView(
                  latestObservation: viewModel.latestObservation,
                ),
                const SizedBox(height: 20),
                TideInformationView(predictions: viewModel.tidePredictions),
                const SizedBox(height: 20),
                WaveChart(buoyObservations: viewModel.buoyObservations),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CurrentWaveView extends StatelessWidget {
  final BuoyObservation? latestObservation;

  const CurrentWaveView({super.key, this.latestObservation});

  @override
  Widget build(BuildContext context) {
    // Format values for display, showing "N/A" if null.
    final waveHeightString = latestObservation?.waveHeightInFeet?.toStringAsFixed(1) ?? "N/A";
    final airTempString = latestObservation?.airTempInFahrenheit?.toStringAsFixed(1) ?? "N/A";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Current Conditions", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: DataCard(title: "Wave Height", value: "$waveHeightString ft")),
            const SizedBox(width: 16),
            Expanded(child: DataCard(title: "Air Temp", value: "$airTempString °F")),
          ],
        ),
      ],
    );
  }
}

class DataCard extends StatelessWidget {
  final String title;
  final String value;

  const DataCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54)),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class TideInformationView extends StatelessWidget {
  final List<TidePrediction> predictions;

  const TideInformationView({super.key, required this.predictions});

  // Helper to format the time string from the API.
  String _formatTime(String dateString) {
    try {
      if (dateString.isEmpty) return 'N/A';
      final dateTime = DateTime.parse(dateString);
      return DateFormat.jm().format(dateTime.toLocal()); // e.g., 5:08 PM
    } catch (e) {
      return dateString; // Fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Tides (Boston Harbor)", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
           elevation: 2,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
           child: Padding(
             padding: const EdgeInsets.all(8.0),
             child: Column(
              children: predictions.map((p) {
                final isHighTide = p.type == "H";
                return ListTile(
                  leading: Icon(
                    isHighTide ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isHighTide ? Colors.blue : Colors.green,
                  ),
                  title: Text("${isHighTide ? 'High' : 'Low'}: ${_formatTime(p.t)}"),
                  trailing: Text("${p.v} ft", style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
           ),
        ),
      ],
    );
  }
}

class WaveChart extends StatelessWidget {
  final List<BuoyObservation> buoyObservations;

  const WaveChart({super.key, required this.buoyObservations});

  @override
  Widget build(BuildContext context) {
    // Convert our observation data into chart spots.
    final spots = buoyObservations
      .where((obs) => obs.waveHeight != null) // Filter out entries with no wave height data
      .map((obs) {
        // Data is newest first, so we reverse it for a chronological chart.
        return FlSpot(obs.time.millisecondsSinceEpoch.toDouble(), obs.waveHeight!);
      })
      .toList().reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("24-Hour Wave Height", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: SizedBox(
              height: 250,
              child: spots.isEmpty ? const Center(child: Text("No wave data to display.")) : LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 6 * 60 * 60 * 1000, // Show a label every 6 hours
                      getTitlesWidget: (value, meta) {
                        final date = DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(DateFormat.j().format(date)), // e.g., 5 PM
                        );
                      },
                    )),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xff37434d), width: 1)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
