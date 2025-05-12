import 'package:flutter/material.dart';
import 'account_info_page.dart';
import 'privacy_policy_page.dart';
import 'app_guide_page.dart';
import 'company_info_page.dart';
import 'technology_page.dart';
import 'faq_page.dart';

class DescriptionPage extends StatelessWidget {
  final List<_DescriptionItem> items = [
    _DescriptionItem('계정 정보', AccountInfoPage()),
    _DescriptionItem('보행 데이터 관리', PrivacyPolicyPage()),
    _DescriptionItem('앱 사용법', AppGuidePage()),
    _DescriptionItem('앱 제작자 소개', CompanyInfoPage()),
    _DescriptionItem('사용된 기술 및 기능', TechnologyPage()),
    _DescriptionItem('자주 묻는 질문', FAQPage()),
  ];

  DescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('소개', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            title: Text(item.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => item.page),
            ),
          );
        },
      ),
    );
  }
}

class _DescriptionItem {
  final String title;
  final Widget page;
  const _DescriptionItem(this.title, this.page);
}
