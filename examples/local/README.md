# Local example

Applies circuit-oracle-free to a throwaway Rocky Linux 9 container with systemd. You need Conn3x and Podman, about 2 GB of memory free and 10 GB of disk. The example accepts the [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html) for you in `main.tf`, so read them first.

Rocky Linux 9 because Oracle builds Database Free for it on both x86_64 and aarch64, so the example runs on an Apple silicon Mac too. For Rocky Linux 10 on x86_64, set `CONTAINERFILE` to Conn3x's `test/images/rocky10/Containerfile`.

Oracle's preinstall package raises the `oracle` user's locked-memory limit, and `su` won't open a session for it when the container's limit is lower, so `up.sh` lifts it. That's simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
export TF_VAR_admin_password="Ex$(openssl rand -hex 8)1"
conn3x init
conn3x apply
conn3x plan
```

The apply downloads about 1.5 GB and creates the database, which takes a few minutes. The second plan says `No changes.` To log in to the pluggable database as `SYSTEM`:

```sh
ssh -t -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  runuser -u oracle -- env ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree \
  /opt/oracle/product/26ai/dbhomeFree/bin/sqlplus system@//127.0.0.1:1521/FREEPDB1
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`.

`./down.sh` removes the container, its volumes, the key and the state.
