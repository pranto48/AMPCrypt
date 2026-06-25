import subprocess
import re
import os

def main():
    try:
        # Run git command to count commits
        result = subprocess.run(['git', 'rev-list', '--count', 'HEAD'], capture_output=True, text=True, check=True)
        commit_count = int(result.stdout.strip())
    except Exception as e:
        print(f"Error getting git commit count: {e}")
        return

    major = commit_count // 100
    minor = commit_count % 100
    version_str = f"V{major}.{minor:02d}"
    print(f"Computed Version: {version_str} (Commits: {commit_count})")

    # 1. Write lib/core/version.dart
    os.makedirs('lib/core', exist_ok=True)
    with open('lib/core/version.dart', 'w') as f:
        f.write(f"// Generated file. Do not edit.\n")
        f.write(f"const String kAppVersion = '{version_str}';\n")
    print("Updated lib/core/version.dart")

    # 2. Update pubspec.yaml
    pubspec_path = 'pubspec.yaml'
    if os.path.exists(pubspec_path):
        with open(pubspec_path, 'r') as f:
            content = f.read()
        
        # Replace version: line
        new_version_line = f"version: {major}.{minor}.0+{commit_count}"
        updated_content = re.sub(r'^version:\s*.*$', new_version_line, content, flags=re.MULTILINE)
        
        with open(pubspec_path, 'w') as f:
            f.write(updated_content)
        print(f"Updated pubspec.yaml version to: {major}.{minor}.0+{commit_count}")

if __name__ == '__main__':
    main()
