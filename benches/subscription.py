from ectf25.utils.decoder import DecoderIntf
from ectf25_design.gen_subscription import gen_subscription
from ectf25_design.encoder import Encoder
import argparse
import time
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    args = parser.parse_args()

    decoder = DecoderIntf(args.port)

    secrets = open('global.secrets', 'rb').read()
    channel = 1
    subscription = gen_subscription(secrets=secrets, device_id=0xdeadbeef, start=1, end=2**64 - 2, channel=channel)

    t = time.perf_counter()
    decoder.subscribe(subscription)
    t = time.perf_counter() - t
    print("TIME", t)

if __name__ == "__main__":
    main()
