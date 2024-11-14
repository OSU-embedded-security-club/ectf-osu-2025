#!/bin/sh

export id="0x11111125"
export boot_message="Component boot"
export attestation_location="McLean"
export attestation_date="08/08/08"
export attestation_customer="Fritz"

nix-shell --run 'poetry run ectf_build_comp -d . -on comp -od . -id "${id}" -b "${boot_message}" -al "${attestation_location}" -ad "${attestation_date}" -ac "${attestation_customer}"'
