import 'package:flutter/material.dart';
import 'account_info_page.dart';
import 'privacy_policy_page.dart';
import 'app_guide_page.dart';
import 'company_info_page.dart';
import 'technology_page.dart';
import 'faq_page.dart';

class DescriptionPage extends StatelessWidget {
  DescriptionPage({super.key});

  final List<_DescriptionItem> items = [
    _DescriptionItem('보행 데이터 관리', PrivacyPolicyPage()),
    _DescriptionItem('앱 사용법', AppGuidePage()),
    _DescriptionItem('앱 제작자 소개', CompanyInfoPage()),
    _DescriptionItem('사용된 기술 및 기능', TechnologyPage()),
    _DescriptionItem('자주 묻는 질문', FAQPage()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.amber,
        title: const Text('소개'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountInfoPage()),
                );
              },
              child: Row(
                children: const [
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: AssetImage('assets/images/profile.jpg'),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '전수영님',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => item.page),
                  );
                },
                child: Text(
                  item.title,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _DescriptionItem {
  final String title;
  final Widget page;

  _DescriptionItem(this.title, this.page);
}
