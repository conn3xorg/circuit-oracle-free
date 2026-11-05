output "connect_strings" {
  description = "Easy Connect strings for the container database and its pluggable database on each host, from the host itself."
  value = {
    for name in keys(var.hosts) : name => {
      cdb = "//127.0.0.1:1521/FREE"
      pdb = "//127.0.0.1:1521/FREEPDB1"
    }
  }
}

output "oracle_home" {
  description = "Oracle home on each host, which holds sqlplus and lsnrctl in bin."
  value       = "/opt/oracle/product/26ai/dbhomeFree"
}
