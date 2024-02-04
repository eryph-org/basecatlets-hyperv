#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${hostname}
    username: ${username}
    # Generated via: printf vagrant | mkpasswd -m sha-512 -S vagrant. -s
    password: "${password_hash}"
  early-commands:
    # otherwise packer tries to connect and exceed max attempts:
    - systemctl stop ssh
  ssh:
    install-server: true
  packages:
    - linux-azure
  storage:
    layout:
      name: direct
    swap:
      size: 0
