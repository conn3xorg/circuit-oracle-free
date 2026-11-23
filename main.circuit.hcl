# Facts give each host's Rocky Linux release and architecture, which pick
# Oracle's RPM. Oracle builds Database Free for EL9 on x86_64 and aarch64,
# and for EL10 on x86_64 only.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = self.os_id == "rocky"
      error_message = "Host ${each.key} is ${self.os_id}. This circuit supports Rocky Linux only."
    }

    postcondition {
      condition     = contains(keys(local.preinstall), "el${split(".", self.os_version)[0]}.${self.arch}")
      error_message = "Oracle builds no Database Free RPM for Rocky Linux ${self.os_version} on ${self.arch}, the release and architecture of host ${each.key}. It builds for Rocky Linux 9 on x86_64 and aarch64, and Rocky Linux 10 on x86_64."
    }
  }
}

locals {
  # Which build each host gets, such as el10.x86_64.
  build = { for name, f in data.conn3x_host.facts : name => "el${split(".", f.os_version)[0]}.${f.arch}" }

  # Oracle's preinstall package sets up the oracle user, kernel settings and
  # limits, and pulls in what the database needs. For hosts other than
  # Oracle Linux, Oracle publishes it on yum.oracle.com. The SHA-256s are the
  # ones on Oracle's download page.
  preinstall = {
    "el9.x86_64"  = { file = "oracle-ai-database-preinstall-26ai-1.0-1.el9.x86_64.rpm", repo = "OL9/appstream/x86_64", sha256 = "6a25ab29277f5af2d301d90b2d60a82357bbacfac7d8d9eddce126eb40cecb54" }
    "el9.aarch64" = { file = "oracle-ai-database-preinstall-26ai-1.0-2.el9.aarch64.rpm", repo = "OL9/appstream/aarch64", sha256 = "b30fef31bc21c9006f41db1faf1487a15a82d5b721e8b34aa478ff378d722e54" }
    "el10.x86_64" = { file = "oracle-ai-database-preinstall-26ai-1.0-1.el10.x86_64.rpm", repo = "OL10/appstream/x86_64", sha256 = "9e70e660a2ef4a6fc7f930d243f80a4326a9bded38a926ca92fdb77a9b25de40" }
  }

  v       = var.oracle_free_version
  package = "oracle-ai-database-free-26ai"
  rpm     = { for name, b in local.build : name => "${local.package}-${local.v}.${b}.rpm" }

  home      = "/opt/oracle/product/26ai/dbhomeFree"
  init      = "/etc/init.d/oracle-free-26ai"
  passwords = "/etc/conn3x/oracle-free/password"
  cache     = "/var/tmp/conn3x-oracle-free"

  hosts_template = "/etc/cloud/templates/hosts.redhat.tmpl"

  # The source address of the default IPv4 route, read on the host each
  # time, since a container's changes when it restarts.
  route_ip = "ip=$(ip -4 -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \\([0-9.]*\\).*/\\1/p');"

  # Downloads an RPM beside the others in the cache, keeps it only if its
  # SHA-256 matches, installs it, and removes it, so the 1.5 GB database RPM
  # doesn't stay on disk.
  install = <<-EOT
    set -e
    mkdir -p -m 0700 ${local.cache}
    cd ${local.cache}
    trap 'rm -f "$f" "$f.part"' EXIT
    curl -sSfL -o "$f.part" "$url"
    echo "$sum  $f.part" | sha256sum -c --quiet -
    mv "$f.part" "$f"
    dnf -y -q install "./$f"
  EOT

  # The password only goes to a listener port held by the oracle user.
  held = <<-EOT
    held() { u=$(id -u oracle); cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk -v u="$u" '$4 == "0A" && $2 ~ /:05F1$/ { n++; if ($8 != u) b = 1 } END { exit !(n && !b) }'; }
  EOT

  # Logs in to the pluggable database over the listener as SYSTEM with the
  # password from the root-only file. The password reaches sqlplus on stdin.
  login = <<-EOT
    ${local.held}
    login() { held && { printf 'connect system/"%s"@//127.0.0.1:1521/FREEPDB1\nset heading off feedback off\nselect '"'"'conn3x-ok'"'"' from dual;\n' "$(head -n1 ${local.passwords})"; } | runuser -u oracle -- env ORACLE_HOME=${local.home} ${local.home}/bin/sqlplus -S -L /nolog 2>&1 | grep -qx 'conn3x-ok'; }
  EOT
}

circuit "oracle_free" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # curl fetches the RPMs, and ip finds the host's address. Oracle's
  # configure script prints the connect strings with hostname. Minimal
  # images leave out the last two.
  step "tools" {
    for_each = toset(["curl", "iproute", "hostname"])
    package {
      name = item.value
    }
  }

  # Oracle's listener setup refuses a host name that resolves only to
  # loopback, which is what cloud images such as DigitalOcean's write in
  # /etc/hosts. Where that's so, this maps the name to the address of the
  # default route too, in /etc/hosts and in the template cloud-init writes
  # it from at boot.
  step "hosts_entry" {
    command {
      command = <<-EOT
        ${local.route_ip}
        [ -n "$ip" ] || { echo 'Host ${each.key} has no default IPv4 route, so the circuit cannot tell which address its name should resolve to. Map the name to the address in /etc/hosts.' >&2; exit 1; }
        l="$ip $(hostname)"
        grep -qxF "$l" /etc/hosts || echo "$l" >> /etc/hosts
        [ ! -f ${local.hosts_template} ] || grep -qxF "$l" ${local.hosts_template} || echo "$l" >> ${local.hosts_template}
      EOT
      unless  = "${local.route_ip} getent ahostsv4 \"$(hostname)\" | awk '$1 !~ /^127\\./' | grep -q . && { [ ! -f ${local.hosts_template} ] || grep -qxF \"$ip $(hostname)\" ${local.hosts_template}; }"
    }
  }

  step "preinstall" {
    command {
      command = "f=${local.preinstall[local.build[each.key]].file} url=https://yum.oracle.com/repo/OracleLinux/${local.preinstall[local.build[each.key]].repo}/getPackage/${local.preinstall[local.build[each.key]].file} sum=${local.preinstall[local.build[each.key]].sha256}\n${local.install}"
      unless  = "rpm -q --quiet oracle-ai-database-preinstall-26ai"
    }
  }

  # Installing the RPM unpacks the Oracle home. The database comes later,
  # from configure.
  step "database_rpm" {
    command {
      command = "f=${local.rpm[each.key]} url=https://download.oracle.com/otn-pub/otn_software/db-free/${local.rpm[each.key]} sum=${var.oracle_free_sha256[local.build[each.key]]}\n${local.install}"
      unless  = "[ \"$(rpm -q --qf '%%{VERSION}-%%{RELEASE}' ${local.package} 2>/dev/null)\" = '${local.v}' ]"
    }
  }

  step "password_dir" {
    directory {
      path = dirname(local.passwords)
      mode = "0700"
    }
  }

  # The password lands in a root-only file, never in state or the plan.
  # Twice, since configure asks for it and then for its confirmation.
  step "password" {
    file {
      path       = local.passwords
      content_wo = "${var.admin_password}\n${var.admin_password}\n"
    }
  }

  # configure reads this only once, when it creates the database. Left
  # empty, it picks the first free port from 1521 up, and a database the
  # circuit can't find; set, configure stops if 1521 is taken.
  step "listener_port" {
    line {
      path   = "/etc/sysconfig/oracle-free-26ai.conf"
      regexp = "^LISTENER_PORT="
      line   = "LISTENER_PORT=1521"
    }
    depends_on = [conn3x_command.oracle_free__database_rpm]
  }

  # Creates the FREE container database with its FREEPDB1 pluggable
  # database and the listener on port 1521. The password reaches it on
  # stdin. It takes a few minutes, and runs once: the data files stay.
  step "configure" {
    command {
      command = "${local.init} configure < ${local.passwords}"
      creates = "/opt/oracle/oradata/FREE/FREEPDB1"
    }
  }

  # The RPM ships a SysV script, which systemd only runs through its
  # generator, where there is one. This unit runs it directly, so the
  # database starts at boot on Rocky Linux 9 and 10 alike.
  step "unit" {
    file {
      path    = "/etc/systemd/system/oracle-free-26ai.service"
      content = <<-EOT
        [Unit]
        Description=Oracle AI Database Free
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=${local.init} start
        ExecStop=${local.init} stop
        TimeoutStartSec=600
        TimeoutStopSec=600

        [Install]
        WantedBy=multi-user.target
      EOT
    }
  }

  step "reload" {
    service_action {
      action   = "daemon-reload"
      triggers = { unit = conn3x_file.oracle_free__unit[each.key].revision }
    }
  }

  # configure leaves the database running, outside the unit. Starting the
  # unit then finds it up, so nothing restarts.
  step "running" {
    service {
      name    = "oracle-free-26ai"
      state   = "started"
      enabled = true
    }
    depends_on = [conn3x_service_action.oracle_free__reload, conn3x_command.oracle_free__configure]
  }

  # SYS, SYSTEM and PDBADMIN share the password. When SYSTEM can't log in
  # with it, such as after a change to admin_password, this sets all three
  # through the oracle user's own login, which needs no password. It waits
  # for the listener first, which can take a minute after a boot. unless is
  # checked at plan time, before the password file changes, so the file's
  # revision makes the apply check again.
  step "admin_password" {
    command {
      command = <<-EOT
        ${local.login}
        for _ in $(seq 60); do held && break; sleep 5; done
        login && exit 0
        pw=$(head -n1 ${local.passwords})
        printf 'whenever sqlerror exit failure\nalter user sys identified by "%s";\nalter user system identified by "%s";\nalter session set container = FREEPDB1;\nalter user pdbadmin identified by "%s";\n' "$pw" "$pw" "$pw" | runuser -u oracle -- env ORACLE_HOME=${local.home} ORACLE_SID=FREE ${local.home}/bin/sqlplus -S -L / as sysdba >/dev/null || exit 1
        login || { echo 'SYSTEM still could not log in with admin_password after it was set. See /opt/oracle/diag.' >&2; exit 1; }
      EOT
      unless  = "${local.login} login"
      triggers = {
        configure = conn3x_command.oracle_free__configure[each.key].revision
        password  = conn3x_file.oracle_free__password[each.key].revision
      }
    }
    depends_on = [conn3x_service.oracle_free__running]
  }
}
