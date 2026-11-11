# Extra backend settings when state lives in the local emulator. The S3
# endpoint itself is passed by the Makefile, because the port can change.
# The access key is the shared-services account id, which is how the
# emulator knows which account the bucket belongs to. It is not a secret.

access_key                  = "444444444444"
secret_key                  = "emulator"
use_path_style              = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
