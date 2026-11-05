variable "hosts" {
  type        = any
  description = "Rocky Linux hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "accept_oracle_license" {
  type        = bool
  description = "Set to true to accept the Oracle Free Use Terms and Conditions, https://www.oracle.com/downloads/licenses/oracle-free-license.html, which Oracle AI Database Free is released under. The circuit downloads and installs nothing without it."

  validation {
    condition     = var.accept_oracle_license
    error_message = "Oracle AI Database Free is released under the Oracle Free Use Terms and Conditions, https://www.oracle.com/downloads/licenses/oracle-free-license.html. Read them, and set accept_oracle_license = true if you accept them."
  }
}

variable "admin_password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Password for the SYS, SYSTEM and PDBADMIN accounts. Pass it at run time with -var or TF_VAR_admin_password; it never reaches state or the plan."

  # Oracle's configure script refuses most punctuation, and asks for upper
  # and lower case and a digit.
  validation {
    condition = (
      can(regex("^[A-Za-z][A-Za-z0-9_#]{7,29}$", var.admin_password)) &&
      can(regex("[A-Z]", var.admin_password)) &&
      can(regex("[a-z]", var.admin_password)) &&
      can(regex("[0-9]", var.admin_password))
    )
    error_message = "admin_password must be 8 to 30 characters: letters, digits, _ and #, starting with a letter, with at least one uppercase letter, one lowercase letter and one digit."
  }
}

variable "oracle_free_version" {
  type        = string
  default     = "23.26.3-1"
  description = "Release of the oracle-ai-database-free-26ai RPM, such as \"23.26.3-1\". Change oracle_free_sha256 with it. Raising it installs the new RPM over the old one."

  validation {
    condition     = can(regex("^23\\.26\\.[0-9]+-[0-9]+$", var.oracle_free_version))
    error_message = "oracle_free_version must be a 26ai Free RPM release, such as \"23.26.3-1\"."
  }
}

variable "oracle_free_sha256" {
  type = map(string)
  default = {
    "el9.x86_64"  = "895fc9df794685b515c4ac83f104dbdfb657eb0e92c41e45c58302fb8fd53e44"
    "el9.aarch64" = "b2a087b8e6d67d99f0cd9b950429b4afd58b71991fd05b5d6254ac84cade94e1"
    "el10.x86_64" = "ddaae3565cdd1b9c0d6eb35f7c1ae630a83068dfbadf31fe7b1c6e169eaa5798"
  }
  description = "SHA-256 of each build of the RPM, from Oracle's download page, by build: el9.x86_64, el9.aarch64 and el10.x86_64. Change it with oracle_free_version."

  validation {
    condition     = alltrue([for k, v in var.oracle_free_sha256 : contains(["el9.x86_64", "el9.aarch64", "el10.x86_64"], k) && can(regex("^[0-9a-f]{64}$", v))])
    error_message = "oracle_free_sha256 maps el9.x86_64, el9.aarch64 or el10.x86_64 to a SHA-256 in lowercase hex."
  }
}
