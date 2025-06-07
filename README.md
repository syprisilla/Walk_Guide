
# Walk_Guide

## OSS Project

- [App Link](#app-link)  
- [Project Summary](#project-summary)
  - [Purpose](#purpose)
- [Requirements](#requirements)
- [How to Use](#how-to-use)
  - [로딩페이지 (Loading Page)](#로딩페이지-loading-page)
  - [로그인 화면 (Login Screen)](#로그인-화면-login-screen)
  - [회원가입 (Sign Up)](#회원가입-sign-up)
  - [닉네임 페이지 (Nickname Page)](#닉네임-페이지-nickname-page)
  - [메인화면 (Main Screen)](#메인화면-main-screen)
  - [객체 탐지 (Object Detection)](#객체-탐지-object-detection)
  - [실시간 보행 속도 분석 화면 (Real-Time Speed Analysis)](#실시간-보행-속도-분석-화면-real-time-speed-analysis)
  - [설정페이지 (Settings Page)](#설정페이지-settings-page)
  - [관리 페이지 (Admin Page)](#관리-페이지-admin-page)
  - [계정 정보 페이지 (Account Info Page)](#계정-정보-페이지-account-info-page)
- [Installation & Run Guide](#installation--run-guide)
- [Tech Stack](#tech-stack)
- [How to Contribute](#how-to-contribute)
- [Team: S.CORE](#team-score)
- [License](#license)

---

## App Link

https://drive.google.com/file/d/1Mnj2sZQgT0129a2JXpbDrVpF1TO4RGWT/view?usp=drive_link



---
## Requirements

- cupertino_icons==1.0.8  
- pedometer==4.1.1  
- sensors_plus==6.1.1  
- permission_handler==12.0.0+1  
- url_launcher==6.2.5  
- camera==0.10.5+9  
- google_mlkit_object_detection==0.11.0  
- google_mlkit_commons==0.6.0  
- isolate==2.1.1  
- hive==2.2.3  
- hive_flutter==1.1.0  
- path_provider==2.0.15  
- flutter_tts==3.8.2  
- fl_chart==0.71.0  
- firebase_core==2.27.0  
- firebase_auth==4.17.4  
- cloud_firestore==4.13.3  
- google_sign_in==6.1.4  
- shared_preferences==2.2.2  
- flutter_map==6.1.0  
- geolocator==11.0.0  
- latlong2==0.9.0  
- build_runner==2.4.6  
- hive_generator==2.0.1  
- test==1.25.15  
- flutter_lints==5.0.0  



## Project summary

**Walk_Guide**는 시각장애인을 위한 객체 인지 기반 안내 시스템입니다.  
이 시스템은 카메라를 통해 사용자의 주변 사물을 실시간으로 인식하고,  
인식된 객체 정보를 음성으로 안내하여 사용자의 실내·외 이동을  
안전하고 효율적으로 돕습니다.

## Purpose
시각장애인은 실내·외를 이동할 때 주변 사물을 파악하는 데 어려움을 겪습니다.  
Walk_Guide는 이러한 문제를 해결하기 위해 개발되었습니다.  
카메라를 통해 객체를 인식하고, 실시간으로 음성 안내를 제공함으로써  
사용자가 도움 없이도 스스로 주변 환경을 인지할 수 있도록 돕는 것을  
목표로 합니다.  



## How to use
### 로딩페이지
<img src="https://github.com/user-attachments/assets/a795a8d4-f1be-4f1d-87ec-13396d2fcdae" alt="image" width="200"/>

<img src="https://github.com/user-attachments/assets/fbf48c76-a8f3-4caa-bdf1-30fa3b09ea1b" alt="image" width="200"/>


앱을 처음 실행하면  
**WalkGuide의 아이콘이 표시된 로딩 화면이 약 4~5초간 보여집니다.**

로딩이 완료되면 자동으로 로그인 화면으로 전환되어  
사용자는 앱의 기능을 바로 이용할 수 있습니다.

### 로그인 화면

<img src="https://github.com/user-attachments/assets/8abc9a66-8cf1-4e8a-b9ef-594d1df9dddc" alt="로그인 화면" width="300"/>

앱을 실행하면 “WalkGuide에 오신 것을 환영합니다”라는 음성 메시지가 자동으로 재생되어  
시각장애인 사용자에게 앱이 시작되었음을 안내합니다.

이후 로그인 화면에서는 두 가지 방식으로 로그인이 가능합니다:

- **기존 이메일/비밀번호 로그인**  
- **Google 계정으로 로그인**

아직 계정이 없다면 **회원가입**을 통해 계정을 생성할 수 있으며,  
회원가입 과정 또한 음성 안내를 통해 단계별로 쉽게 진행할 수 있도록 설계되어 있습니다.

<br/>

<img src="https://github.com/user-attachments/assets/cc0cdb9c-af26-4ddb-afa3-26f37aa2ca3e" alt="image" width="500"/>




가입되어 있지 않은 이메일이나 잘못된 비밀번호를 입력하면  
위와 같이 **빨간색 경고 메시지로 로그인 실패: 다시 시도해 주세요**라는 문구가 나타나며,  
사용자에게 입력 오류를 명확하게 안내해줍니다.


### 회원가입

<img src="https://github.com/user-attachments/assets/50def514-0ce5-4c4a-b611-4c07d0d66f9a" alt="회원가입 화면" width="300"/>

**회원가입 페이지**에 들어가면  
이메일과 비밀번호를 입력할 수 있는 입력창이 나타납니다.

처음 앱을 이용할 때는 **Google 계정으로 로그인**하는 기능도 제공되며,  
해당 방식으로 최초 로그인 시에는 **닉네임을 입력하는 화면이 한 번만 나타납니다**.

이후부터는 동일한 Google 계정으로 로그인할 경우,  
**닉네임 입력 없이 계정 선택 화면만 표시되어 간편하게 접속**할 수 있습니다.

<br/>

<img src="https://github.com/user-attachments/assets/bec9787e-85d2-4b7d-88e1-f9060f0084f4" alt="비밀번호 오류 메시지" width="300"/>





비밀번호를 6자 미만으로 입력할 경우  
위와 같이 **비밀번호는 6자리 이상이어야 합니다**라는  
오류 메시지가 나타나며 회원가입이 제한됩니다.  
사용자는 **6자 이상의 비밀번호를 입력해야만 정상적으로 가입이 완료**됩니다.

<br/>

<img src="https://github.com/user-attachments/assets/8d2a1bc0-e58f-4428-8e35-c91df6c67d98" alt="이메일 형식 오류 메시지" width="300"/>





또한, 이메일을 잘못된 형식으로 입력할 경우  
**회원가입 실패: 이메일 형식에 맞게 작성해주세요**라는  
오류 메시지가 표시됩니다.  

사용자는 반드시 **example@domain.com** 형태의  
**올바른 이메일 주소 형식**으로 입력해야 정상적으로 회원가입을 완료할 수 있습니다.

### 닉네임 페이지

<img src="https://github.com/user-attachments/assets/827ab323-aa2d-406b-83a0-cb9d5d014703" alt="image" width="300"/>



회원가입을 이메일 형식과 비밀번호 조건에 맞게 완료하면,  
다음으로 **닉네임을 입력하는 페이지**가 표시됩니다.

이 페이지에서 사용자는 앱 내에서 사용할 **자신만의 닉네임을 자유롭게 입력**할 수 있으며,  
입력 후 **‘저장하고 시작하기’** 버튼을 누르면 앱 사용이 본격적으로 시작됩니다.

### 메인화면

<img src="https://github.com/user-attachments/assets/9140fdb6-0363-4e6b-8876-9d837c77a4f8" alt="image" width="300"/>



WalkGuide의 **메인화면**에 들어오면  
“오늘도 즐거운 하루 되세요!”라는 **환영 음성 메시지**가 자동으로 재생되어  
사용자에게 앱이 정상적으로 실행되었음을 알려줍니다.

지도 상에는 **현재 자신의 위치를 나타내는 아이콘**이 표시되며,  
화면 우측에 있는 **위치 추적 버튼**을 누르면  
지도를 다른 방향으로 이동하고 있더라도 **자신의 현재 위치로 즉시 이동**할 수 있습니다.

하단에는 다음과 같은 주요 기능 버튼이 배치되어 있습니다:

- **보행 시작하기**
- **분석**
- **설정**
- **관리페이지**

### 객체 탐지

<img src="https://github.com/user-attachments/assets/828304e3-dd59-4c4e-b682-951f416dce9b" alt="image" width="500"/>



**보행 시작하기** 버튼을 누르면,  
카메라가 실행되며 실시간으로 주변 **객체를 인식**하는 화면으로 전환됩니다.

화면 우측에는 다음 정보들이 표시되는 **보행 위젯**이 나타납니다:

- 현재까지의 **걸음 수**
- 사용자의 **평균 속도**
- 실시간으로 계산된 **즉시 속도**

인식된 객체는 **초록색 직사각형**으로 표시되며,  
객체의 **크기(큰/중간/작은)** 와 **방향(왼쪽/오른쪽/정면)** 을 분석하여  
"좌측에 큰 장애물이 있습니다"와 같은 형태로  
사용자에게 **음성 안내**를 제공합니다.

이를 통해 시각장애인은 주변 상황을 명확하게 인지하고  
장애물을 피해 안전하게 이동할 수 있습니다.


### 실시간 보행 속도 분석 화면

<img src="https://github.com/user-attachments/assets/60dd6fab-2268-4e7e-9519-5bb12c10c590" alt="보행 데이터 분석 화면" width="300"/>

Walk_Guide는 Android의 `sensor_pulse` 기능을 활용하여  
사용자의 걸음 수와 보행 속도를 실시간으로 측정합니다.

측정된 데이터는 사용자의 보행 패턴 분석에 활용되며,  
다음과 같은 화면을 통해 시각적으로 확인할 수 있습니다.

분석 페이지에는 다음과 같은 기능들이 포함되어 있어,  
사용자는 자신의 평균 속도와 걸음 수 변화 추이를 한눈에 파악할 수 있습니다:

- **오늘 하루 속도 변화**
- **최근 일주일 평균 속도 변화**
- **최근 일주일 걸음 수 변화**
- **세션 다시보기**

이 데이터를 기반으로, Walk_Guide는 사용자에게  
실시간 피드백을 제공하며 안전하고 효율적인 보행을 돕습니다.

<br/>

<img src="https://github.com/user-attachments/assets/2033f98c-a6df-4479-b627-ad8a60bc4098" alt="image" width="300"/>


또한, 화면을 아래로 스크롤하면  
**데이터 초기화**, **백업**, **복원** 기능을 수행할 수 있는 버튼이 제공됩니다.

- **초기화**: 앱에 저장된 모든 보행 데이터를 삭제합니다.  
- **백업**: 현재까지의 데이터를 로컬 `.json` 파일로 저장할 수 있습니다.  
- **복원**: 백업한 `.json` 파일을 불러와 이전 데이터를 다시 불러올 수 있습니다.

### 설정페이지

<img src="https://github.com/user-attachments/assets/d70ff440-f50b-4ab3-a713-f7da8b924740" alt="image" width="300"/>



**설정 페이지**에 들어가면 사용자는 두 가지 음성 안내 기능을 켜고 끌 수 있습니다.

- **음성 안내**  
  앱 실행 시 “환영합니다” 등의 음성 메시지를 재생할지 여부를 설정할 수 있습니다.

- **페이지 이동 음성 안내**  
  버튼을 터치할 때 해당 페이지의 목적지를 **음성으로 안내**하는 기능입니다.

이 두 기능은 각각의 스위치를 통해 **ON/OFF 조절**이 가능하며,  
해당 기능이 꺼져 있을 경우 앱은 **음성 메시지를 출력하지 않습니다**.

### 관리 페이지

<img src="https://github.com/user-attachments/assets/2f79dd53-6721-4266-8640-73932ec59f8d" alt="image" width="300"/>



메인 페이지 오른쪽 상단의 **햄버거 메뉴(≡)** 버튼을 누르면  
**관리 페이지**로 이동할 수 있습니다.

이 페이지에서는 사용자의 **별명(닉네임)** 과 함께  
앱의 다양한 설명 및 기능 안내를 확인할 수 있습니다.

관리 페이지에는 다음과 같은 항목들이 제공됩니다:

- **보행 데이터 관리**  
  기록된 보행 데이터를 확인하거나 초기화할 수 있습니다.

- **앱 사용법**  
  앱의 기본적인 사용 흐름과 각 기능에 대한 설명이 정리되어 있습니다.

- **앱 제작자 소개**  
  개발자 및 팀원 정보가 표시됩니다.

- **사용된 기술 및 기능**  
  앱에 적용된 주요 기술 스택과 기능 구현 방식이 요약되어 있습니다.

- **자주 묻는 질문**  
  사용 중 자주 접할 수 있는 문제와 해결 방법이 정리되어 있습니다.

이 페이지는 앱을 처음 사용하는 사용자나,  
기능을 사용하다가 **궁금한 점이나 어려움이 생겼을 때 참고할 수 있는 안내 센터**의 역할을 합니다.

### 계정 정보 페이지

<img src="https://github.com/user-attachments/assets/feba99e5-67c7-4712-99fc-b8951e86978a" alt="image" width="300"/>



**관리 페이지에서 닉네임을 선택하면 계정 정보 페이지로 이동**하게 됩니다.  
현재 로그인된 사용자의 **닉네임**, **이메일**, 그리고 **로그인 방식**이 표시됩니다.

Google 계정으로 로그인한 경우에는  
"로그인 방식: Google 로그인"과 같이 명확하게 안내되며,  
이메일 주소와 함께 계정 정보를 쉽게 확인할 수 있습니다.

하단에는 **빨간색 ‘로그아웃’ 버튼**이 있어  
누르면 현재 계정에서 로그아웃되며,  
다시 로그인 화면으로 돌아가 **다른 계정으로 재로그인**할 수 있습니다.



## Installation & Run Guide

### 1. 저장소 클론

```bash
git clone https://github.com/syprisilla/Walk_Guide.git
cd Walk_Guide
```

### 2. Flutter 패키지 설치

```bash
flutter pub get
```

### 3. 앱 실행

```bash
flutter run
```

> **참고**: Flutter가 설치되어 있어야 하며, 연결된 디바이스 또는 에뮬레이터가 필요합니다.

## Tech Stack

- **Flutter**: UI 개발
- **Dart**: 프로그래밍 언어
- **Firebase**: 인증 및 데이터베이스
- **C++ / CMake**: 네이티브 기능 구현
- **Swift**: iOS 플랫폼 지원
- **HTML**: 일부 웹 구성 요소

## How to Contribute

1. 이 저장소를 포크합니다.
2. 새로운 브랜치를 생성합니다: `git checkout -b feature/새로운기능`
3. 변경 사항을 커밋합니다: `git commit -m '새로운 기능 추가'`
4. 브랜치에 푸시합니다: `git push origin feature/새로운기능`
5. Pull Request를 생성합니다.
   
## Team: S.CORE

| 이름 | 역할 | GitHub | Email |
|------|------|--------|-------|
| **김병우(팀장)** | 바운더리 박스 구현, 객체 감지 정확성 향상 및 버그 수정 | [https://github.com/xnoa03](https://github.com/xnoa03) | xnoa03@naver.com |
| **권오섭** | 카메라 초기설정, ML Kit 기반 객체 감지 로직 구현 | [https://github.com/kos6490](https://github.com/kos6490) | kos-6490@naver.com |
| **전수영** | 로그인과 회원가입 기능 담당, 앱 전체 UI 구성 | [https://github.com/Jeonsooyoung](https://github.com/Jeonsooyoung) | jsooyoung05@gmail.com |
| **김선영** | 보행자 속도 분석 기능 담당, 앱 음성 안내 기능 담당 | [https://github.com/syprisilla](https://github.com/syprisilla) | kt28805546@gmail.com |



## License

이 프로젝트는 MIT 라이선스 하에 제공됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참고하세요.



