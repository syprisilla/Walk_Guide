import 'package:flutter/material.dart';

class DescriptionPage extends StatelessWidget {
  final List<String> titles = [
    '계정 정보',
    '개인정보처리방침',
    '이용 약관',
    '사업자 정보',
    '오픈 소스 라이브러리',
    '앱 업데이트',
  ];

  final List<Widget> detailPages = [
    AccountInfoPage(),
    PrivacyPolicyPage(),
    TermsPage(),
    CompanyInfoPage(),
    OpenSourcePage(),
    AppUpdatePage(),
  ];

  DescriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('소개', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: titles.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(titles[index]),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => detailPages[index],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AccountInfoPage extends StatelessWidget {
  const AccountInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('계정 정보')),
      body: Center(child: Text('계정 정보 내용')),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('개인정보처리방침')),
      body: Center(child: Text('개인정보처리방침 내용')),
    );
  }
}

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('이용 약관')),
      body: Center(child: Text('이용 약관 내용')),
    );
  }
}

class CompanyInfoPage extends StatelessWidget {
  const CompanyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('사업자 정보')),
      body: Center(child: Text('사업자 정보 내용')),
    );
  }
}

class OpenSourcePage extends StatelessWidget {
  const OpenSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('오픈 소스 라이브러리')),
      body: Center(child: Text('오픈 소스 라이브러리 내용')),
    );
  }
}

class AppUpdatePage extends StatelessWidget {
  const AppUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('앱 업데이트')),
      body: Center(child: Text('앱 업데이트 내용')),
    );
  }
}
