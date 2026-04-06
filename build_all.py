
import json
import subprocess
import sys

def get_buildable_attributes(data, path=""):
    """Recursively finds all buildable attributes in the flake data."""
    attributes = []
    for key, value in data.items():
        new_path = f"{path}.{key}" if path else key
        if isinstance(value, dict):
            if value.get("type") in ["app", "package", "derivation"]:
                attributes.append(new_path)
            else:
                attributes.extend(get_buildable_attributes(value, new_path))
    return attributes

def main():
    """Main function to build all flake outputs."""
    print("Getting flake outputs...")
    try:
        result = subprocess.run(
            ["nix", "flake", "show", "--all-systems", "--json"],
            capture_output=True,
            text=True,
            check=True,
        )
        flake_data = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error getting flake outputs: {e}", file=sys.stderr)
        if isinstance(e, subprocess.CalledProcessError):
            print(f"Stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)

    buildable_categories = ["packages", "apps", "checks"]
    attributes_to_build = []
    for category in buildable_categories:
        if category in flake_data:
            attributes_to_build.extend(get_buildable_attributes(flake_data[category], category))

    print(f"Found {len(attributes_to_build)} attributes to build.")

    failures = {}
    for i, attr in enumerate(attributes_to_build):
        print(f"--- Building attribute {i+1}/{len(attributes_to_build)}: {attr} ---")
        try:
            subprocess.run(
                ["nix", "build", f".#{attr}", "--print-build-logs"],
                check=True,
                capture_output=True,
                text=True,
            )
            print(f"SUCCESS: {attr}")
        except subprocess.CalledProcessError as e:
            print(f"FAILURE: {attr}", file=sys.stderr)
            failures[attr] = e.stderr
            print(e.stderr, file=sys.stderr)

    if failures:
        print("\n--- Summary of Failures ---")
        for attr, error_log in failures.items():
            print(f"\n--- Failed to build: {attr} ---")
            error_lines = error_log.strip().split('\n')
            for line in error_lines[-20:]:
                print(line)
        sys.exit(1)
    else:
        print("\n--- All attributes built successfully! ---")

if __name__ == "__main__":
    main()
