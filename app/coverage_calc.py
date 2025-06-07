import os


target_files = [
    'lib/map/map_screen.dart',
    'lib/services/auth_service_testable.dart',
    'lib/ObjectDetection/mlkit_object_detection.dart',
    'lib/ObjectDetection/bounding_box_painter.dart',
    'lib/ObjectDetection/camera_initialization_ui.dart',
    'lib/ObjectDetection/camera_screen.dart',
    'lib/ObjectDetection/object_painter.dart',
    'lib/ObjectDetection/name_tag_painter.dart',
    'lib/services/firestore_service.dart',
    'lib/services/statistics_service.dart',
    'lib/analytics_dashboard_page.dart',
    'lib/main_testable.dart',
    'lib/login_page.dart',
    'lib/nickname_input_page.dart',
    'lib/real_time_speed_service.dart',
    'lib/signup_page.dart',
    'lib/step_counter_page.dart',
    'lib/user_profile.dart',
    'lib/voice_guide_service.dart',
    'lib/walk_session.dart'
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


total_stmts = 0
total_miss = 0

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

                total_stmts += total_lines
                total_miss += missed

    if not target_found:
        print(f"{target_file:<45} {'N/A':<6} {'N/A':<6} {'0.0%':>6}")

# TOTAL summary
if total_stmts > 0:
    total_coverage = (total_stmts - total_miss) / total_stmts * 100
    print(separator)
    print(f"{'TOTAL':<45} {total_stmts:<6} {total_miss:<6} {total_coverage:>5.1f}%")

