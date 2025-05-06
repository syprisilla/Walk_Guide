import 'package:flutter/material.dart';

class DescriptionPage extends StatelessWidget {
  final List<String> titles = [
    '계정 정보',
    '보행 데이터 관리',
    '앱 사용법',
    '앱 제작자 소개',
    '사용된 기술 및 기능',
    '자주 묻는 질문',
  ];

  final List<Widget> detailPages = [
    AccountInfoPage(),
    PrivacyPolicyPage(),
    AppGuidePage(), // 변경된 부분
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundImage: AssetImage('assets/images/profile.jpg'),
            ),
            const SizedBox(height: 16),
            const Text(
              'syprisilla',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 20),
                SizedBox(width: 8),
                Text('가입한 날짜: 2017년 2월'),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.email_outlined, size: 20),
                SizedBox(width: 8),
                Text('이메일: syprisilla@example.com'),
              ],
            ),
          ],
        ),
      ),
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

class AppGuidePage extends StatelessWidget {
  const AppGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('앱 사용법')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: const [
            Text(
              'WalkGuide 앱에 오신 것을 환영합니다!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Divider(height: 24, thickness: 1.2),
            Text(
              'WalkGuide는 시각장애인의 안전한 보행을 돕기 위해 설계된 앱입니다.\n'
              '이 앱을 통해 사용자는 실시간으로 장애물 정보를 음성으로 안내받고, '
              '자신의 걸음 속도에 맞는 맞춤형 피드백을 받을 수 있습니다.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 24),
            Text(
              '1. 실시간 안내 기능',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            SizedBox(height: 6),
            Text(
              '- 사용자의 보행 속도에 맞춰 음성 안내 제공\n'
              '- 장애물이 감지되면 즉시 경고\n'
              '- AI가 패턴을 학습하여 최적화된 타이밍 안내',
            ),
            SizedBox(height: 24),
            Text(
              '2. 보행 데이터 분석',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            SizedBox(height: 6),
            Text(
              '- 걸음 수, 속도, 정지 구간 등을 시각화하여 보여줌\n'
              '- 최근 일주일 평균 속도 그래프 제공\n'
              '- 보행 데이터 백업 및 복원 기능 지원',
            ),
            SizedBox(height: 24),
            Text(
              '3. 기타',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            SizedBox(height: 6),
            Text(
              '- 로그인 시 사용자 이름 호출 기능\n'
              '- 설정에서 음성 속도 조절 가능',
            ),
          ],
        ),
      ),
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
