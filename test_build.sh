#!/usr/bin/env bash

#test the build process 

set -euo pipefail

BASE="$HOME/devincubator/ansible"
cd "$BASE"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" ; FAILED=1; }
info() { echo "[INFO] $*"; }
FAILED=0

# ---------- 1) Ansible sanity ----------
info "Checking Ansible is installed and reachable"
if ansible --version >/dev/null 2>&1; then
  pass "ansible found"
else
  fail "ansible missing"
fi

# ensure ansible.cfg is in place (project-local)
if [[ ! -f "$BASE/ansible.cfg" ]]; then
  fail "ansible.cfg missing at $BASE/ansible.cfg"
else
  pass "ansible.cfg present"
fi

info "Syntax check"
if ansible-playbook --syntax-check playbooks/local.yml >/dev/null; then
  pass "syntax ok"
else
  fail "syntax errors"
fi

info "Dry-run (--check)"
if ansible-playbook --check playbooks/local.yml | tee /tmp/ansible_check.log >/dev/null; then
  pass "dry-run executed"
else
  fail "dry-run did not complete"
fi

info "Idempotence run (expect changed=0 on second run)"
ansible-playbook playbooks/local.yml | tee /tmp/ansible_run1.log >/dev/null || true
ansible-playbook playbooks/local.yml | tee /tmp/ansible_run2.log >/dev/null || true
if grep -Eq "changed=0.*failed=0" /tmp/ansible_run2.log; then
  pass "idempotence confirmed (second run changed=0, failed=0)"
else
  fail "idempotence not achieved (review /tmp/ansible_run2.log)"
fi

# ---------- 2) Base packages ----------
info "Verifying base packages"
BASE_PKGS=(build-essential curl wget git unzip htop net-tools software-properties-common ca-certificates gnupg lsb-release make cmake ninja-build pkg-config jq tmux screen minicom picocom)
BASE_MISSING=0
for p in "${BASE_PKGS[@]}"; do
  if ! dpkg -s "$p" >/dev/null 2>&1; then
    echo "  missing: $p"
    BASE_MISSING=1
  fi
done
if [[ $BASE_MISSING -eq 0 ]]; then
  pass "base packages installed"
else
  fail "some base packages missing"
fi

# ---------- 3) Docker ----------
info "Checking Docker CLI presence"
if command -v docker >/dev/null 2>&1; then
  pass "docker cli present: $(docker --version 2>/dev/null | head -n1)"
else
  fail "docker cli missing"
fi

info "Checking Docker service"
systemctl is-enabled docker >/dev/null 2>&1 && pass "docker service enabled" || fail "docker service not enabled"
systemctl is-active  docker >/dev/null 2>&1 && pass "docker service active"  || fail "docker service not active"

info "Checking current user docker group membership"
if id -nG "$USER" | grep -qw docker; then
  pass "user is in docker group"
else
  fail "user not in docker group (run: sudo usermod -aG docker $USER && newgrp docker)"
fi

info "Checking Docker socket permissions"
if [[ -S /var/run/docker.sock ]]; then
  ls -l /var/run/docker.sock || true
  pass "docker.sock present"
else
  fail "docker.sock missing"
fi

info "Running hello-world via docker group subshell (no logout required)"
if sg docker -c 'docker run --rm hello-world' >/tmp/docker_hello.log 2>&1; then
  pass "hello-world container ran successfully via docker group"
else
  cat /tmp/docker_hello.log || true
  fail "hello-world container failed (review log above)"
  info "Try: newgrp docker   (then: docker run --rm hello-world)"
fi

# ---------- 4) VS Code ----------
info "Verifying VS Code installation"
if command -v code >/dev/null 2>&1; then
  pass "VS Code present: $(code --version | head -n1)"
  EXPECT_EXTS=(ms-vscode-remote.remote-containers ms-vscode.cpptools ms-python.python platformio.platformio-ide)
  if code --list-extensions >/tmp/code_exts.txt 2>/dev/null; then
    EXT_MISSING=0
    for e in "${EXPECT_EXTS[@]}"; do
      if ! grep -qx "$e" /tmp/code_exts.txt; then
        echo "  missing extension: $e"
        EXT_MISSING=1
      fi
    done
    if [[ $EXT_MISSING -eq 0 ]]; then
      pass "VS Code extensions installed"
    else
      fail "some VS Code extensions missing"
    fi
  else
    info "VS Code CLI extension query failed (likely no GUI session). Launch VS Code once, then re-run test."
  fi
else
  fail "VS Code not installed"
fi

# ---------- 5) STM32 toolchain ----------
info "Checking STM32 toolchain"
command -v arm-none-eabi-gcc >/dev/null 2>&1 && pass "arm-none-eabi-gcc: $(arm-none-eabi-gcc --version | head -n1)" || fail "arm-none-eabi-gcc missing"
command -v openocd          >/dev/null 2>&1 && pass "openocd: $(openocd --version 2>/dev/null | head -n1)"       || fail "openocd missing"
command -v dfu-util         >/dev/null 2>&1 && pass "dfu-util: $(dfu-util --version 2>/dev/null | head -n1)"     || fail "dfu-util missing"

info "Checking STLink udev rule"
if [[ -f /etc/udev/rules.d/49-stlinkv2.rules ]]; then
  pass "udev rule present"
else
  fail "udev rule missing"
fi

# ---------- 6) Summary ----------
if [[ $FAILED -eq 0 ]]; then
  echo "-------------------------------------------------------------------"
  echo "ALL TESTS PASSED"
  echo "Tip: if you were just added to the docker group, run: newgrp docker"
  echo "-------------------------------------------------------------------"
  exit 0
else
  echo "-------------------------------------------------------------------"
  echo "SOME TESTS FAILED (see [FAIL] lines above)."
  echo "Re-run a specific area, e.g.: ansible-playbook playbooks/local.yml --tags docker"
  echo "-------------------------------------------------------------------"
  exit 1
fi
