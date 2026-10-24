import 'package:flutter/material.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';

class MissionPage extends StatefulWidget {
  final Mission? mission;

  const MissionPage({Key? key, this.mission}) : super(key: key);

  @override
  _MissionPageState createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _targetAmount;
  late DateTime _startDate;
  late DateTime _endDate;

  late final TextEditingController _targetController;

  @override
  void initState() {
    super.initState();
    if (widget.mission != null) {
      _name = widget.mission!.name;
      _targetAmount = widget.mission!.targetAmount;
      _startDate = widget.mission!.startDate;
      _endDate = widget.mission!.endDate;
    } else {
      _name = '';
      _targetAmount = 0.0;
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(Duration(days: 30));
    }

    _targetController = TextEditingController(text: _targetAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  void _saveMission() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final mission = Mission(
        name: _name,
        targetAmount: _targetAmount,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (widget.mission == null) {
        await MoneyStorage().addMission(mission);
      } else {
        await MoneyStorage().updateMission(mission);
      }
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mission == null ? 'Create Mission' : 'Edit Mission'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                initialValue: _name,
                decoration: InputDecoration(labelText: 'Mission Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
                onSaved: (value) => _name = value!,
              ),
              TextFormField(
                controller: _targetController,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Target Amount'),
                validator: (value) {
                  final v = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
                  if (v == null) return 'Please enter a valid amount';
                  if (v < 0) return 'Must be >= 0';
                  return null;
                },
                onTap: () async {
                  final v = await showAmountCalculatorSheet(
                    context,
                    title: 'Target Amount',
                    initialValue: double.tryParse(_targetController.text),
                    allowZero: true,
                  );
                  if (v == null) return;
                  _targetController.text = v.toStringAsFixed(2);
                },
                onSaved: (value) {
                  _targetAmount = double.parse((value ?? '0').trim().replaceAll(',', '.'));
                },
              ),
              // ... Add date pickers for startDate and endDate ...
              ElevatedButton(
                onPressed: _saveMission,
                child: Text(widget.mission == null ? 'Create' : 'Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
