from pathlib import Path
from ectf25.utils.decoder import DecoderIntf
from ectf25_design.gen_subscription import gen_subscription
from ectf25_design.encoder import Encoder
import argparse
import ast
import json
import traceback


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("data")
    parser.add_argument("secrets")
    parser.add_argument("port")
    args = parser.parse_args()
    data = ast.literal_eval(Path(args.data).read_text())
    secrets = Path(args.secrets).read_bytes()
    print(secrets)
    port = args.port

    decoder = DecoderIntf(port)
    encoder = Encoder(secrets)

    device_id = 0xDEADBEEF
    bad_device_id = 0xCAFEBABE

    for name, commands in data.items():
        print(f"\n\n\n\n======== RUNNING {name} ============\n\n\n\n")
        for command in commands:
            try:
                op, *args = command.split()
                if op == "subscribe" or op == "bad_subscribe":
                    subscription_device_id = (
                        device_id if op == "subscribe" else bad_device_id
                    )
                    channel, start, end = args
                    try:
                        subscription = gen_subscription(
                            secrets,
                            subscription_device_id,
                            int(start),
                            int(end),
                            int(channel),
                        )
                    except Exception as e:
                        print("CAUGHT ENCODER ERROR")
                        subscription = f"ERROR: Encoder exception: {e}".encode()
                    decoder.subscribe(subscription)
                elif op == "list":
                    decoder.list()
                elif op == "decode":
                    channel, timestamp, *frame = args
                    frame = ast.literal_eval(" ".join(frame)).encode()
                    try:
                        encoded = encoder.encode(int(channel), frame, int(timestamp))
                    except Exception as e:
                        print("CAUGHT ENCODER ERROR")
                        encoded = f"ERROR: Encoder exception: {e}".encode()
                    decoder.decode(encoded)
                elif op == "flash":
                    input("Please flash and then press enter")
                elif op == "power_cycle":
                    input("Please power cycle and then press enter")
                else:
                    raise ValueError(op)
            except Exception as e:
                traceback.print_exception(e)
                input(f"Caught error in {name}, press enter to continue")


if __name__ == "__main__":
    main()
