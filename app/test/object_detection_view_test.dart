import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:walk_guide/ObjectDetection/object_detection_view.dart';
import 'package:fake_async/fake_async.dart'; // 두 번째 테스트를 위해 사용

// 테스트용 Mock CameraDescription 정의
const mockBackCamera = CameraDescription(
  name: 'mock_cam_0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ObjectDetectionView Widget Tests (feature_isolate branch version - with modified dispose)', () {
    testWidgets('카메라 리스트가 비어있을 때 "사용 가능한 카메라가 없습니다" 메시지를 표시해야 합니다', (WidgetTester tester) async {
      // 1. 위젯 빌드
      await tester.pumpWidget(
        const MaterialApp(
          home: ObjectDetectionView(cameras: []),
        ),
      );

      // 2. initState에서 호출된 setState로 인해 위젯이 다시 빌드되고 UI가 안정화될 때까지 기다립니다.
      //    ObjectDetectionView의 dispose가 수정되어 "Timer still pending" 오류가 발생하지 않으므로
      //    pumpAndSettle이 안정적으로 동작할 것으로 기대합니다.
      await tester.pumpAndSettle();

      // 3. 예상되는 오류 메시지가 표시되는지 확인합니다.
      expect(find.textContaining('사용 가능한 카메라가 없습니다', findRichText: true), findsOneWidget);

      // 4. 테스트 종료 시 위젯이 자동으로 dispose됩니다. 수정된 dispose 로직 덕분에 타이머 문제가 없습니다.
    });

    testWidgets('카메라가 제공되면, 초기 "로딩" 후 "초기화 실패" 메시지를 표시해야 합니다', (WidgetTester tester) async {
      await fakeAsync((async) async {
        // 1. 위젯 빌드
        await tester.pumpWidget(
          MaterialApp(
            home: ObjectDetectionView(cameras: [mockBackCamera]),
          ),
        );

        // 2. 초기 빌드 및 initState 내의 첫 상태 반영 ("카메라 초기화 중...")
        async.flushMicrotasks(); // initState 내의 비동기 호출(예: setState)로 인한 마이크로태스크 처리
        await tester.pump();      // 첫 프레임 빌드

        // 3. 초기 로딩 상태 확인
        expect(find.text('카메라 초기화 중...'), findsOneWidget, reason: '"카메라 초기화 중..." 메시지가 초기에 표시되어야 합니다.');
        expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '로딩 인디케이터가 초기에 표시되어야 합니다.');

        // 4. _spawnIsolates().then(_initializeCamera) 및 내부 CameraController.initialize() 실패,
        //    그로 인한 setState까지의 시간을 충분히 진행시킵니다.
        //    테스트 환경에서는 실제 카메라 접근이 불가능하므로 초기화는 실패할 것입니다.
        async.elapse(const Duration(seconds: 3)); // 비동기 작업(Isolate 생성, 카메라 초기화 시도)에 충분한 시간 부여
        async.flushMicrotasks(); // 모든 중간 마이크로태스크 처리
        await tester.pump();      // 상태 변경 후 UI 업데이트 (오류 메시지 표시 기대)

        // 5. 카메라 초기화 실패 메시지 확인
        expect(find.textContaining('카메라 시작에 실패했습니다', findRichText: true), findsOneWidget,
            reason: '카메라 초기화 실패 메시지가 표시되어야 합니다.');
        // 로딩 관련 UI는 사라져야 합니다.
        expect(find.text('카메라 초기화 중...'), findsNothing,
            reason: '"카메라 초기화 중..." 메시지는 실패 후 사라져야 합니다.');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: '로딩 인디케이터는 실패 후 사라져야 합니다.');

        // 6. 위젯을 트리에서 제거하여 dispose 로직 발동
        await tester.pumpWidget(const SizedBox.shrink());
        async.flushMicrotasks(); // dispose 호출 관련 마이크로태스크 처리
        await tester.pump();      // 제거된 상태 UI 반영

        // 7. dispose 내부의 수정된 로직(테스트 시 delay 없음)을 고려하여 짧은 시간만 진행
        //    혹시 모를 microtask나 짧은 비동기 정리 작업을 위해 남겨둡니다.
        async.elapse(const Duration(milliseconds: 50)); 
        async.flushMicrotasks();
        await tester.pump();      // 최종 안정화
      });
    });
  });
}