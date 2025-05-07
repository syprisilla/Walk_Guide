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
    AppGuidePage(),
    CompanyInfoPage(),
    TechnologyPage(),
    FAQPage(),
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
      appBar: AppBar(title: Text('보행 데이터 관리')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ListTile(
            leading: Icon(Icons.storage_outlined, size: 30),
            title: Text('데이터 저장 위치'),
            subtitle:
                Text('모든 보행 데이터는 로컬(Hive)에 안전하게 저장됩니다. 인터넷 연결 없이도 사용 가능합니다.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.backup_outlined, size: 30),
            title: Text('백업 및 복원'),
            subtitle: Text('보행 데이터는 JSON 파일 형식으로 백업할 수 있으며, 필요시 복원할 수 있습니다.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.delete_outline, size: 30),
            title: Text('데이터 초기화'),
            subtitle:
                Text('설정에서 전체 보행 데이터를 삭제하여 초기화할 수 있습니다. 되돌릴 수 없으니 주의하세요.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.security_outlined, size: 30),
            title: Text('보안 안내'),
            subtitle: Text(
                '데이터는 사용자 로컬 저장소에만 저장되며 외부 서버로 전송되지 않아 개인 정보가 안전하게 보호됩니다.'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.settings_backup_restore, size: 30),
            title: Text('세션별 데이터 관리'),
            subtitle: Text('각 보행 세션은 구분되어 저장되며, 원하는 세션만 삭제 또는 복원할 수 있습니다.'),
          ),
        ],
      ),
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
      appBar: AppBar(title: Text('앱 제작자 소개')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: const [
          Text('충북대학교',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text('팀명: SCORE', style: TextStyle(fontSize: 16)),
          Divider(height: 32),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('김병우'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('권오섭'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('전수영'),
            subtitle: Text('~~~~~'),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('김선영'),
            subtitle: Text('~~~~~'),
          ),
          Divider(height: 32),
          Text(
            '제작 배경:\n시각장애인의 보행 안전을 돕기 위해 WalkGuide 앱을 개발했습니다. '
            '사용자의 보행 데이터를 수집하고 AI 분석을 통해 맞춤형 음성 피드백을 제공하는 것이 핵심 기능입니다.',
            style: TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class TechnologyPage extends StatelessWidget {
  const TechnologyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('사용된 기술 및 기능')),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('센서 사용'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('걸음 수 측정을 위해 sensors_plus 사용'),
              )
            ],
          ),
          ExpansionTile(
            title: Text('AI 기반 안내'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('보행 속도를 학습하여 맞춤 안내 제공'),
              )
            ],
          ),
          ExpansionTile(
            title: Text('음성 안내'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Flutter TTS를 통해 음성 피드백 제공'),
              )
            ],
          ),
          ExpansionTile(
            title: Text('로컬 저장소 Hive'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('보행 데이터를 Hive에 저장하고 복원'),
              )
            ],
          ),
        ],
      ),
    );
  }
}

class FAQPage extends StatelessWidget {
  const FAQPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('자주 묻는 질문')),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('앱을 실행했는데 아무 안내도 들리지 않아요.'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('음성 안내 설정이 꺼져있을 수 있습니다. 설정에서 음성 안내를 켜주세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('보행 데이터가 초기화되었어요.'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('로그인 방식이 바뀌었는지 확인해 주세요. 동일한 계정으로 다시 로그인해보세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('앱이 갑자기 종료돼요.'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('최신 버전으로 업데이트하거나, 오류가 지속되면 고객센터로 문의해주세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('피드백을 보내고 싶어요.'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('앱 내 문의하기를 통해 피드백을 자유롭게 보내주세요.'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('음성 속도를 조절하고 싶어요.'),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('설정에서 음성 속도를 조절할 수 있습니다.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
