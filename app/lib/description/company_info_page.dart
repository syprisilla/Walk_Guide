import 'package:flutter/material.dart';

class CompanyInfoPage extends StatelessWidget {
  const CompanyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 제작자 소개')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: const [
          Text('충북대학교', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text('팀명: SCORE', style: TextStyle(fontSize: 16)),
          Divider(height: 32),
          ListTile(leading: Icon(Icons.person), title: Text('김병우'), subtitle: Text('~~~~~')),
          ListTile(leading: Icon(Icons.person), title: Text('권오섭'), subtitle: Text('~~~~~')),
          ListTile(leading: Icon(Icons.person), title: Text('전수영'), subtitle: Text('~~~~~')),
          ListTile(leading: Icon(Icons.person), title: Text('김선영'), subtitle: Text('~~~~~')),
        ],
      ),
    );
  }
}
