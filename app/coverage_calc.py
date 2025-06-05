import os

# 타겟 디렉토리 및 특정 파일을 정의합니다.

target_object_detection_dir = 'lib/'
target_map_screen_file = 'lib/map/map_screen.dart'

lcov_path = 'coverage/lcov.info'

if not os.path.exists(lcov_path):
    print("❌ lcov.info not found.")
    exit()

with open(lcov_path, 'r') as file:
    lines = file.readlines()

current_file = None
executed_lines_for_current_file = 0
total_lines_for_current_file = 0

overall_total_lines = 0
overall_executed_lines = 0
found_any_target_file = False

header = f"{'File':<60} {'Stmts':<6} {'Miss':<6} {'Cover':<6}"
separator = "-" * len(header)
print(header)
print(separator)

def process_and_print_file_coverage():
    global found_any_target_file, overall_total_lines, overall_executed_lines
    # current_file이 None이 아니고, 실제 내용(total_lines_for_current_file > 0)이 있는 경우에만 처리
    if current_file and total_lines_for_current_file > 0:
        is_in_object_detection_dir = current_file.startswith(target_object_detection_dir) and current_file.endswith('.dart')
        is_map_screen_file = current_file == target_map_screen_file

        if is_in_object_detection_dir or is_map_screen_file:
            found_any_target_file = True
            missed = total_lines_for_current_file - executed_lines_for_current_file
            coverage = (executed_lines_for_current_file / total_lines_for_current_file) * 100 if total_lines_for_current_file > 0 else 0.0
            print(f"{current_file:<60} {total_lines_for_current_file:<6} {missed:<6} {coverage:>5.1f}%")

            overall_total_lines += total_lines_for_current_file
            overall_executed_lines += executed_lines_for_current_file

for line in lines:
    line_stripped = line.strip()
    if line_stripped.startswith('SF:'):
        # 새로운 SF 라인을 만나면, 이전 파일에 대한 커버리지 정보를 먼저 처리하고 출력
        process_and_print_file_coverage()

        # 새 파일 정보로 초기화
        current_file = line_stripped.split('SF:')[1].replace("\\", "/")
        executed_lines_for_current_file = 0
        total_lines_for_current_file = 0

    elif line_stripped.startswith('DA:'):
        if current_file: # SF 라인 이후에만 DA 라인이 의미가 있음
            # DA 라인은 현재 파일이 타겟인지 여부와 관계없이 일단 파싱은 하지만,
            # process_and_print_file_coverage 함수 내에서 타겟 파일일 경우에만 overall 합계에 더해짐
            # 또한, lcov.info에서 DA 라인은 소스코드의 실행 가능한 라인을 의미하므로
            # 이 라인이 나올 때마다 total_lines_for_current_file를 증가시켜야 합니다.
            is_in_object_detection_dir = current_file.startswith(target_object_detection_dir) and current_file.endswith('.dart')
            is_map_screen_file = current_file == target_map_screen_file
            if is_in_object_detection_dir or is_map_screen_file:
                total_lines_for_current_file += 1 # DA 라인은 커버리지 대상 라인임
                _, count_str = line_stripped.split(',')
                if int(count_str) > 0:
                    executed_lines_for_current_file += 1

    elif line_stripped.startswith('end_of_record'):
        # end_of_record를 만나면, 현재 파일에 대한 커버리지 정보를 처리하고 출력
        process_and_print_file_coverage()
        current_file = None # 파일 정보 초기화

# 루프 종료 후 마지막 파일 처리 (파일의 마지막에 end_of_record가 없는 경우 대비)
if current_file:
    process_and_print_file_coverage()


if found_any_target_file:
    print(separator)
    overall_missed_lines = overall_total_lines - overall_executed_lines
    overall_coverage = (overall_executed_lines / overall_total_lines) * 100 if overall_total_lines > 0 else 0.0
    print(f"{'Total':<60} {overall_total_lines:<6} {overall_missed_lines:<6} {overall_coverage:>5.1f}%")
else:
    print(f"No target files (in {target_object_detection_dir} or {target_map_screen_file}) found in the coverage report.")