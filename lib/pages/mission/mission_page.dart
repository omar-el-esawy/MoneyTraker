import 'package:flutter/material.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/store/money_storage.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    MoneyStorage moneyStorage = MoneyStorage();
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
                initialValue: _targetAmount.toString(),
                decoration: InputDecoration(labelText: 'Target Amount'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || double.tryParse(value) == null) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
                onSaved: (value) => _targetAmount = double.parse(value!),
              ),
              // ... Add date pickers for startDate and endDate ...
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    final mission = Mission(
                      id: widget.mission?.id ?? DateTime.now().toString(),
                      name: _name,
                      targetAmount: _targetAmount,
                      startDate: _startDate,
                      endDate: _endDate,
                    );
                    if (widget.mission == null) {
                      moneyStorage.addMission(mission);
                    } else {
                      moneyStorage.updateMission(mission);
                    }
                    Navigator.pop(context);
                  }
                },
                child: Text(widget.mission == null ? 'Create' : 'Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
