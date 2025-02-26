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
    data = json.loads(Path(args.data).read_text())

    secrets = Path(args.secrets).read_bytes()
    print(secrets)
    port = args.port

    decoder = DecoderIntf(port)
    encoder = Encoder(secrets)

    device_id = 0xDEADBEEF
    bad_device_id = 0xCAFEBABE

    curr_timestamp = 0
    output = {}
    for name, commands in data.items():
        print(f"\n\n\n\n======== RUNNING {name} ============\n\n\n\n")
        outcommands = []
        for command in commands:
            should_error = False
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
                        should_error = True
                    # decoder.subscribe(subscription)
                elif op == "list":
                    decoder.list()
                elif op == "decode":
                    channel, timestamp, *frame = args
                    if int(timestamp) < curr_timestamp:
                        should_error = True
                    curr_timestamp = int(timestamp)
                    frame = ast.literal_eval(" ".join(frame)).encode()
                    try:
                        encoded = encoder.encode(int(channel), frame, int(timestamp))
                    except Exception as e:
                        print("CAUGHT ENCODER ERROR")
                        encoded = f"ERROR: Encoder exception: {e}".encode()
                        should_error = True
                    # decoder.decode(encoded)
                elif op == "flash":
                    pass
                    # input("Please flash and then press enter")
                elif op == "power_cycle":
                    curr_timestamp = 0
                    # input("Please power cycle and then press enter")
                    pass
                outcommands.append({"command": command, "expected": not should_error})
            except Exception as e:
                traceback.print_exception(e)
                # input(f"Caught error in {name}, press enter to continue")
                pass
        output[name] = outcommands
    Path("data.modified.json").write_text(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
