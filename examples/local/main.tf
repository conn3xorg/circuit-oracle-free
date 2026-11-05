variable "port" {
  type    = number
  default = 2222
}

# Pass it at run time, such as with TF_VAR_admin_password.
variable "admin_password" {
  type      = string
  ephemeral = true
  sensitive = true
}

module "oracle_free" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  # Read https://www.oracle.com/downloads/licenses/oracle-free-license.html
  # first: this accepts it.
  accept_oracle_license = true
  admin_password        = var.admin_password
}
