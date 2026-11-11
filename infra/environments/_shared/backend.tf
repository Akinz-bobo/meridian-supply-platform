# Shared by every layer of every environment through a symbolic link.
#
# The backend is configured at init time: the bucket and its settings come
# from backend.hcl, and the state key is built from the environment and
# layer by the Makefile. That keeps this file identical everywhere.

terraform {
  backend "s3" {}
}
