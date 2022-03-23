import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:employees_app/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:overlapping_time/overlapping_time.dart';

import 'models/pair_model.dart';

class Employees extends State<MyApp> {
  late List<List<dynamic>> projectsData;
  late List<Pair> pairs;

  List<PlatformFile>? _paths;
  final String? _extension = "csv";
  final FileType _pickingType = FileType.custom;

  late int maxSum;

  @override
  void initState() {
    super.initState();
    pairs = List<Pair>.empty(growable: true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text("Employee pairs")),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: Container(
                width: 200,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.0),
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromRGBO(111, 198, 25, 1),
                      Color.fromRGBO(159, 235, 83, 1)
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    primary: Colors.transparent,
                    onSurface: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                  onPressed: _openFileExplorer,
                  child: const Center(
                    child: Text(
                      "Select CSV",
                      style: TextStyle(
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                color: Colors.white,
                height: pairs.isNotEmpty ? 30 : 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Employee #1",
                    ),
                    const Text("Employee #2"),
                    const Text("Days worked"),
                    const Text("Project ID"),
                  ],
                ),
              ),
            ),
            ListView.builder(
                shrinkWrap: true,
                itemCount: pairs.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pairs[index].firstEmployeeId.toString()),
                          Text(pairs[index].secondEmployeeId.toString()),
                          Text(pairs[index].daysWorked.toString()),
                          Text(pairs[index].projectId.toString()),
                        ],
                      ),
                    ),
                  );
                }),
          ],
        ),
      ),
    );
  }

  getPairs(filepath) async {
    File f = File(filepath);
    final input = f.openRead();

    final fields = await input
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: "\n", fieldDelimiter: ","))
        .toList();

    var employeeIds = fields.map((e) => e[0]).toSet();
    var projectIds = fields.map((e) => e[1]).toSet();

    for (var projectId in projectIds) {
      List outputList = fields.where((o) => o[1] == projectId).toList();

      if (outputList.length > 1) {
        DateTime now = DateTime.now();
        DateTime formattedDate = DateTime(now.year, now.month, now.day);

        int overlappingDays;
        int firstemployee;
        int secondemployee;

        for (var i = 0; i < outputList.length; i++) {
          final rangeA = DateTimeRange(
            start: getDate(outputList, i, 2),
            end: outputList[i][3] == "NULL"
                ? formattedDate
                : getDate(outputList, i, 3),
          );

          for (var j = i + 1; j < outputList.length; j++) {
            final rangeB = DateTimeRange(
              start: getDate(outputList, j, 2),
              end: outputList[j][3] == "NULL"
                  ? formattedDate
                  : getDate(outputList, j, 3),
            );

            final Map<int, List<ComparingResult>> searchResults = findOverlap(
                ranges: [rangeA, rangeB], allowTouchingRanges: true);

            if (searchResults[2]?.isNotEmpty == true) {
              final DateTimeRange overlappingRange =
                  searchResults[2]?.first.overlappingRange;

              overlappingDays = overlappingRange.duration.inDays;

              firstemployee = outputList[i][0];
              secondemployee = outputList[j][0];

              pairs.add(Pair(
                  firstemployee, secondemployee, overlappingDays, projectId));
            }
          }
        }
      }
    }

    var result = filterPairsBySum(employeeIds.toList());

    setState(() {
      pairs = result;
    });
  }

  getDate(List<dynamic> outputList, int i, int j) {
    var date;
    try {
      date = DateTime.parse(outputList[i][j]);
    } on FormatException {
      date = DateFormat('yyyy/MM/dd').parse(outputList[i][j]);
    }
    return date;
  }

  List<Pair> filterPairsBySum(List<dynamic> employeeIds) {
    List<Pair> filteredById = <Pair>[];
    List<Pair> results = <Pair>[];
    int maxSum = 0;
    int firstIndex = 0;
    int secondIndex = 0;

    for (int i = 0; i < employeeIds.length; i++) {
      var first = employeeIds[i];
      for (var j = i + 1; j < employeeIds.length; j++) {
        var second = employeeIds[j];

        var filteredPairs = pairs
            .where((o) =>
                o.firstEmployeeId == first && o.secondEmployeeId == second)
            .toList();

        if (filteredPairs.isNotEmpty) {
          filteredById.addAll(filteredPairs);

          var pairsSum = filteredPairs
              .map((e) => e.daysWorked)
              .reduce((value, element) => value + element);

          if (pairsSum > maxSum) {
            maxSum = pairsSum;
            firstIndex = first;
            secondIndex = second;
          }
        }
      }
    }

    results.addAll(filteredById.where((element) =>
        element.firstEmployeeId == firstIndex &&
        element.secondEmployeeId == secondIndex));

    return results;
  }

  void _openFileExplorer() async {
    try {
      _paths = (await FilePicker.platform.pickFiles(
        type: _pickingType,
        allowMultiple: false,
        allowedExtensions: (_extension?.isNotEmpty ?? false)
            ? _extension?.replaceAll(' ', '').split(',')
            : null,
      ))
          ?.files;
    } on PlatformException catch (e) {
      // print("Unsupported operation" + e.toString());
    } catch (ex) {}
    if (!mounted) return;
    setState(() {
      getPairs(_paths![0].path);
    });
  }
}
