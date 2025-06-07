# run_test.py
import subprocess

def run_flutter_tests():
    try:
        # 1. Flutter 테스트 실행 + 커버리지 수집
        subprocess.run(["flutter", "test", "--coverage"], check=True)

        # 2. 커버리지 요약 출력
        subprocess.run([
            "dart", "pub", "global", "run",
            "coverage:format_coverage",
            "--lcov", "--in", "coverage/lcov.info", "--summary"
        ], check=True)

        print("\n✅ 테스트 및 커버리지 측정 완료!")

    except subprocess.CalledProcessError as e:
        print("❌ 오류 발생:", e)

if __name__ == "__main__":
    run_flutter_tests()
