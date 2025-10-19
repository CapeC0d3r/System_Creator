#!/usr/bin/env bash

# robust re-run that fixes missing directories and missing git/ansible before creating files
# usage: paste this whole block into your terminal

set -euo pipefail



# base path for the repo
BASE="$HOME/devincubator/ansible"

# start clean if an earlier attempt partially created things
rm -rf "$BASE"
mkdir -p "$BASE"
cd "$BASE"

# create directory structure (absolute paths to avoid CWD mishaps)
install -d "$BASE/inventories/localhost"
install -d "$BASE/playbooks"
install -d "$BASE/roles/base/tasks"
install -d "$BASE/roles/devtools/tasks"
install -d "$BASE/roles/docker/tasks" "$BASE/roles/docker/handlers" "$BASE/roles/docker/defaults"
install -d "$BASE/roles/vscode/tasks" "$BASE/roles/vscode/defaults"
install -d "$BASE/roles/stm32/tasks"

# README (plain text, no nested code fencing)
cat > "$BASE/README.md" <<'EOF'
Development Incubator – Ansible Provisioning
===========================================

This repository defines a reproducible Ubuntu development workstation.

The VM is not the artifact — these playbooks are. Both the incubator VM and
the final workstation are provisioned by the same Ansible roles.

Philosophy
----------
- Reproducible: rebuild the workstation from scratch in minutes.
- Configuration-as-code: no snowflake machines; everything lives here.
- Minimal host: push toolchains into Docker/devcontainers where possible.

Directory Structure
-------------------
ansible/
  inventories/
    localhost/hosts.yaml
  playbooks/
    local.yml
  roles/
    base/      (system updates + essentials)
    devtools/  (developer CLI tools)
    docker/    (docker engine + user group)
    vscode/    (VS Code + extensions)
    stm32/     (ARM toolchains + udev rules)

Quickstart
----------
sudo apt update && sudo apt install -y ansible git
cd ~/devincubator/ansible
ansible-playbook playbooks/local.yml
EOF

# inventory
cat > "$BASE/inventories/localhost/hosts.yaml" <<'EOF'
all:
  hosts:
    localhost:
      ansible_connection: local
EOF

# playbook
cat > "$BASE/playbooks/local.yml" <<'EOF'
---
- name: Provision local development environment
  hosts: localhost
  become: true

  vars:
    docker_users: ["{{ ansible_user_id }}"]
    vscode_extensions:
      - ms-vscode-remote.remote-containers
      - ms-vscode.cpptools
      - ms-python.python
      - platformio.platformio-ide

  roles:
    - { role: base, tags: ["base"] }
    - { role: devtools, tags: ["devtools"] }
    - { role: docker, tags: ["docker"] }
    - { role: vscode, tags: ["vscode"] }
    - { role: stm32, tags: ["stm32"] }
EOF

# role: base
cat > "$BASE/roles/base/tasks/main.yml" <<'EOF'
---
- name: Update apt and upgrade packages
  apt:
    update_cache: yes
    upgrade: dist
  tags: [always]

- name: Install base packages
  apt:
    name:
      - build-essential
      - curl
      - wget
      - git
      - unzip
      - htop
      - net-tools
      - software-properties-common
      - ca-certificates
      - gnupg
      - lsb-release
      - make
      - cmake
      - ninja-build
      - pkg-config
      - jq
      - tmux
      - screen
      - minicom
      - picocom
    state: present

- name: Ensure time synchronization
  service:
    name: systemd-timesyncd
    enabled: true
    state: started
EOF

# role: devtools
cat > "$BASE/roles/devtools/tasks/main.yml" <<'EOF'
---
- name: Install Python toolchain
  apt:
    name:
      - python3
      - python3-pip
      - python3-venv
    state: present

- name: Install CLI tools
  apt:
    name:
      - zsh
      - ripgrep
      - fzf
      - bat
      - tree
    state: present
EOF

# role: docker defaults/handlers/tasks
cat > "$BASE/roles/docker/defaults/main.yml" <<'EOF'
---
docker_users: ["{{ ansible_user_id }}"]
EOF

cat > "$BASE/roles/docker/handlers/main.yml" <<'EOF'
---
- name: restart docker
  service:
    name: docker
    state: restarted
EOF

cat > "$BASE/roles/docker/tasks/main.yml" <<'EOF'
---
- name: Add Docker GPG key
  apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present

- name: Determine correct APT architecture label
  set_fact:
    deb_arch: >-
      {{ {'x86_64':'amd64','aarch64':'arm64'}[ansible_architecture] | default('amd64') }}

- name: Add Docker repository
  apt_repository:
    repo: "deb [arch={{ deb_arch }}] https://download.docker.com/linux/ubuntu {{ ansible_lsb.codename }} stable"
    state: present
    filename: docker

- name: Install Docker
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    update_cache: yes
    state: present
  notify: restart docker

- name: Add users to docker group
  user:
    name: "{{ item }}"
    groups: docker
    append: yes
  loop: "{{ docker_users }}"

- name: Verify docker is working
  command: docker version
  register: docker_version
  changed_when: false
  failed_when: docker_version.rc not in [0]
EOF

# role: vscode defaults/tasks
cat > "$BASE/roles/vscode/defaults/main.yml" <<'EOF'
---
vscode_extensions:
  - ms-vscode-remote.remote-containers
  - ms-vscode.cpptools
  - ms-python.python
  - platformio.platformio-ide
EOF

cat > "$BASE/roles/vscode/tasks/main.yml" <<'EOF'
---
- name: Add Microsoft GPG key
  apt_key:
    url: https://packages.microsoft.com/keys/microsoft.asc
    state: present

- name: Add VS Code repository
  apt_repository:
    repo: "deb [arch={{ deb_arch }}] https://packages.microsoft.com/repos/code stable main"
    state: present
    filename: vscode

- name: Install VS Code
  apt:
    name: code
    update_cache: yes
    state: present

- name: Get installed extensions
  become: false
  shell: "code --list-extensions | tr -d '\\r'"
  args:
    executable: /bin/bash
  register: code_exts
  changed_when: false
  failed_when: false

- name: Install extensions
  become: false
  shell: "code --install-extension {{ item }} --force"
  loop: "{{ vscode_extensions }}"
  when:
    - code_exts.rc == 0
    - item not in code_exts.stdout_lines | default([])
EOF

# role: stm32 tasks
cat > "$BASE/roles/stm32/tasks/main.yml" <<'EOF'
---
- name: Ensure universe repository is enabled
  apt_repository:
    repo: "deb http://archive.ubuntu.com/ubuntu {{ ansible_lsb.codename }} universe"
    state: present

- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600

- name: Install STM32 tools (verbose)
  become: true
  shell: |
    set -e
    echo "[STM32] Updating apt cache..."
    apt-get update -y
    echo "[STM32] Installing toolchain packages..."
    DEBIAN_FRONTEND=readline apt-get install -y \
      gcc-arm-none-eabi \
      gdb-multiarch \
      openocd \
      dfu-util
  args:
    executable: /bin/bash
  register: stm32_install
  changed_when: "'0 upgraded' not in stm32_install.stdout"

- name: Install STLink udev rules
  get_url:
    url: https://raw.githubusercontent.com/stlink-org/stlink/develop/config/udev/rules.d/49-stlinkv2.rules
    dest: /etc/udev/rules.d/49-stlinkv2.rules
    mode: "0644"
  changed_when: false

- name: Reload udev rules
  command: udevadm control --reload-rules
  changed_when: false

- name: Trigger udev
  command: udevadm trigger
  changed_when: false
- name: Install STM32 tools
  apt:
    name:
      - gcc-arm-none-eabi
      - gdb-multiarch
      - openocd
      - dfu-util
    state: present

- name: Install STLink udev rules
  get_url:
    url: https://raw.githubusercontent.com/stlink-org/stlink/develop/config/udev/rules.d/49-stlinkv2.rules
    dest: /etc/udev/rules.d/49-stlinkv2.rules
    mode: "0644"

- name: Reload udev rules
  command: udevadm control --reload-rules
  changed_when: false

- name: Trigger udev events
  command: udevadm trigger
  changed_when: false
EOF

cat > "$BASE/ansible.cfg" <<'EOF'
[defaults]
inventory = ./inventories/localhost/hosts.yaml
roles_path = ./roles
host_key_checking = False
interpreter_python = /usr/bin/python3
stdout_callback = yaml
retry_files_enabled = False
EOF


# initialize git repo and make first commit
#git init
#git add .
#git commit -m "Initial Ansible scaffold with base, devtools, docker, vscode, stm32 roles"

# run the playbook
ansible-playbook "$BASE/playbooks/local.yml"

