import os

target_files = [
    'lib/map/map_screen.dart',
    'lib/services/auth_service_testable.dart',
    'lib/main_testable.dart'
]

lcov_path = 'coverage/lcov.info'

if not os.path.exists(lcov_path):
    print("❌ lcov.info not found.")
    exit()

with open(lcov_path, 'r') as file:
    lines = file.readlines()

header = f"{'File':<45} {'Stmts':<6} {'Miss':<6} {'Cover':<6}"
separator = "-" * len(header)
print(header)
print(separator)

# 모든 파일을 순회하며 검사
for target_file in target_files:
    current_file = None
    executed_lines = 0
    total_lines = 0
    target_found = False

    for line in lines:
        if line.startswith('SF:'):
            current_file = line.strip().split('SF:')[1].replace("\\", "/")
            executed_lines = 0
            total_lines = 0

        elif line.startswith('DA:'):
            total_lines += 1
            _, count = line.strip().split(',')
            if int(count) > 0:
                executed_lines += 1

        elif line.startswith('end_of_record') and current_file:
            if current_file.endswith(target_file.replace("\\", "/")):
                target_found = True
                missed = total_lines - executed_lines
                coverage = (executed_lines / total_lines) * 100 if total_lines > 0 else 0.0
                print(f"{target_file:<45} {total_lines:<6} {missed:<6} {coverage:>5.1f}%")

    if not target_found:
        print(f"{target_file:<45} {'N/A':<6} {'N/A':<6} {'0.0%':>6}")
