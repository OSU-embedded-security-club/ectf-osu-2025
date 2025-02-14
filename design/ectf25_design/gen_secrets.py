"""
Author: Ben Janis
Date: 2025

This source file is part of an example system for MITRE's 2025 Embedded System CTF
(eCTF). This code is being provided only for educational purposes for the 2025 MITRE
eCTF competition, and may not meet MITRE standards for quality. Use this code at your
own risk!

Copyright: Copyright (c) 2025 The MITRE Corporation
"""

import os
import argparse
import json
from pathlib import Path

from loguru import logger

from Crypto.Signature import eddsa

def gen_secrets(channels: list[int]) -> bytes:
    """Generate the contents secrets file

    This will be passed to the Encoder, ectf25_design.gen_subscription, and the build
    process of the decoder

    :param channels: List of channel numbers that will be valid in this deployment.
        Channel 0 is the emergency broadcast, which will always be valid and will
        NOT be included in this list

    :returns: Contents of the secrets file
    """

    # Create a key pair for signing messages.
    keypair = eddsa.import_private_key(os.urandom(32))

    secrets = {
        # Each channel has a hash key derivation tree, which is a binary tree of height 64. The seed is the root of the tree.
        # Children are computed by calculating blake3(node + 'L') or blake3(node + 'R'). The bottom 2**64 nodes give a unique symmetric key for
        # each timestamp. When a subscription is generated, only the nodes neccesary for calculating keys in the subscription's time range are
        # sent to the decoder. See section 4.1 in the design document for details.
        "seeds": {str(channel): os.urandom(24).hex() for channel in channels},

        # A shared symmetric key used to encrypt the entire decode packet, including timestamp and channel ID. This is embedded in each decoder.
        "metadata_key": os.urandom(32).hex(),

        # Subscription packets are encrypted with a unique key for each decoder, computed as `blake3(subscription_salt + device_id)`.
        # This hash is computed at build time and embedded in each decoder, and is computed again in gen_subscription.
        # See section 4.2 in the design document for details.
        "subscription_salt": os.urandom(32).hex(),

        # The Ed25519 keypair used for signing all messages. The public key is embedded in each decoder.
        # See section 4.3 in the design document for details.
        "public_key": keypair.public_key().export_key(format="raw").hex(),
        "private_key": keypair.export_key(format="PEM"),
    }

    return json.dumps(secrets, indent=2).encode()


def parse_args():
    """Define and parse the command line arguments

    NOTE: Your design must not change this function
    """
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Force creation of secrets file, overwriting existing file",
    )
    parser.add_argument(
        "secrets_file",
        type=Path,
        help="Path to the secrets file to be created",
    )
    parser.add_argument(
        "channels",
        nargs="+",
        type=int,
        help="Supported channels. Channel 0 (broadcast) is always valid and will not"
        " be provided in this list",
    )
    return parser.parse_args()


def main():
    """Main function of gen_secrets

    You will likely not have to change this function
    """
    # Parse the command line arguments
    args = parse_args()

    secrets = gen_secrets(args.channels)

    # Print the generated secrets for your own debugging
    # Attackers will NOT have access to the output of this, but feel free to remove
    #
    # NOTE: Printing sensitive data is generally not good security practice
    logger.debug(f"Generated secrets: {secrets}")

    # Open the file, erroring if the file exists unless the --force arg is provided
    with open(args.secrets_file, "wb" if args.force else "xb") as f:
        # Dump the secrets to the file
        f.write(secrets)

    # For your own debugging. Feel free to remove
    logger.success(f"Wrote secrets to {str(args.secrets_file.absolute())}")


if __name__ == "__main__":
    main()
