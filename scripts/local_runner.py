#!/usr/bin/env python3
import argparse
import os
import subprocess
import yaml
import sys
import platform
import json

def parse_nix_yml(path):
    if not os.path.exists(path):
        print(f"Error: {path} not found.")
        return {}
    
    with open(path, 'r') as f:
        try:
            data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            print(f"Error parsing {path}: {e}")
            return {}
    
    jobs = data.get('jobs', {})
    targets = {}
    
    for job_name, job_data in jobs.items():
        # Look for matrix strategy
        strategy = job_data.get('strategy', {})
        matrix = strategy.get('matrix', {})
        if 'target' in matrix:
            targets[job_name] = matrix['target']
    
    return targets

def run_build(target, use_nom=False):
    print(f"\n>>> Building target: {target}")
    
    # Check if target exists as a package or check
    # We'll just try to build it. Nix will tell us if it's missing.
    
    build_cmd = ["nix", "build", f".#{target}", "--print-build-logs"]
    if use_nom:
        # Check if nom is available
        if subprocess.call(["which", "nom"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            build_cmd = ["nom", "build", f".#{target}"]
        else:
            print("Warning: 'nom' (nix-output-monitor) not found, falling back to 'nix build'")
    
    log_dir = os.path.abspath("logs")
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    log_file = os.path.join(log_dir, f"{target}.log")
    
    print(f"Logging to: {log_file}")
    
    with open(log_file, "w") as f:
        try:
            # We want to capture both stdout and stderr
            process = subprocess.Popen(
                build_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            if process.stdout:
                for line in process.stdout:
                    # Print to terminal and log file
                    sys.stdout.write(line)
                    f.write(line)
            
            process.wait()
            
            if process.returncode == 0:
                print(f"\n✅ SUCCESS: {target}")
                return True
            else:
                print(f"\n❌ FAILURE: {target} (Exit code: {process.returncode})")
                return False
                
        except Exception as e:
            print(f"\n🛑 ERROR running build for {target}: {e}")
            f.write(f"ERROR: {e}\n")
            return False

def main():
    parser = argparse.ArgumentParser(description="Local GitHub Actions Runner for Nix")
    parser.add_argument("--list", action="store_true", help="List all available targets from nix.yml")
    parser.add_argument("--target", type=str, help="Specific target to build")
    parser.add_argument("--job", type=str, help="Specific job to run (build-linux or build-macos)")
    parser.add_argument("--all", action="store_true", help="Build all targets for the current platform")
    parser.add_argument("--nom", action="store_true", default=True, help="Use nix-output-monitor (nom) if available (default: True)")
    parser.add_argument("--no-nom", action="store_false", dest="nom", help="Disable nix-output-monitor")
    
    parser.add_argument("--workflow", type=str, help="Path to nix.yml workflow file")
    
    args = parser.parse_args()
    
    workflow_path = args.workflow
    if not workflow_path:
        # Try to find nix.yml in common locations
        workflow_paths = [
            ".github/workflows/nix.yml",
            "Wawona/.github/workflows/nix.yml"
        ]
        for p in workflow_paths:
            if os.path.exists(p):
                workflow_path = p
                break
            
    if not workflow_path:
        print("Error: Could not find .github/workflows/nix.yml. Use --workflow to specify it.")
        sys.exit(1)
        
    job_targets = parse_nix_yml(workflow_path)
    
    if args.list:
        print(f"Loaded targets from {workflow_path}:")
        for job, targets in job_targets.items():
            print(f"\nJob: {job}")
            for t in targets:
                print(f"  - {t}")
        return

    # Determine platform
    plt = platform.system().lower()
    host_job = "build-macos" if plt == "darwin" else "build-linux"
    
    targets_to_run = []
    
    if args.target:
        targets_to_run = [args.target]
    elif args.job:
        if args.job in job_targets:
            targets_to_run = job_targets[args.job]
        else:
            print(f"Error: Job {args.job} not found")
            sys.exit(1)
    elif args.all:
        if host_job in job_targets:
            targets_to_run = job_targets[host_job]
            print(f"Selected all targets for {host_job}")
        else:
            # Fallback: just use all targets from all jobs?
            print(f"Warning: No job found for current platform ({plt}). Checking all jobs...")
            for jt in job_targets.values():
                targets_to_run.extend(jt)
    else:
        parser.print_help()
        sys.exit(0)

    # Dedup
    targets_to_run = list(dict.fromkeys(targets_to_run))

    if not targets_to_run:
        print("No targets selected.")
        sys.exit(0)

    results = {}
    for target in targets_to_run:
        success = run_build(target, use_nom=args.nom)
        results[target] = "SUCCESS" if success else "FAILURE"

    print("\n" + "="*60)
    print(f"{'TARGET':40} | {'RESULT':10}")
    print("-"*60)
    for target, result in results.items():
        status_icon = "✅" if result == "SUCCESS" else "❌"
        print(f"{target:40} | {status_icon} {result}")
    print("="*60)
    
    if any(r == "FAILURE" for r in results.values()):
        sys.exit(1)

if __name__ == "__main__":
    main()
