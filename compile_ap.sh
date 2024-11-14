#!/bin/sh

export ap="ap"
export pin="123456"
export comp_cnt=2
export comp_ids_1="0x11111124"
export comp_ids_2="0x11111125"
export boot_message="Boot"
export replacement_token="1234567899876543"
export ap_out_dir="build"

nix-shell --run 'poetry run ectf_build_ap -d . -on ap -p $pin -t ${replacement_token} -c ${comp_cnt} -ids ${comp_ids_1} -ids ${comp_ids_2} -b ${boot_message}'
