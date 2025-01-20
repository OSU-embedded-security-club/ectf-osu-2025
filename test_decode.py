from ectf25.utils.decoder import DecoderIntf
from ectf25_design.gen_subscription import gen_subscription
from ectf25_design.encoder import Encoder
import argparse
import random
from pathlib import Path
import time

from loguru import logger

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    args = parser.parse_args()

    decoder = DecoderIntf(args.port)

    secrets = Path("secrets/secrets.json").read_bytes()
    channel = 1
    subscription = gen_subscription(secrets=secrets, device_id=0xdeadbeef, start=0, end=10000, channel=channel)
    print(f'{subscription.hex()=}')
    decoder.subscribe(subscription)
    logger.success("Subscribe successful")


    raw_frames = [random.randbytes(64) for _ in range(100)]

    # # Encode all the frames before starting the timer
    encoder = Encoder(secrets=secrets)
    encoded_frames = [encoder.encode(channel=channel, frame=frame, timestamp=i+35) for (i, frame) in enumerate(raw_frames)]

    print(encoded_frames[0].hex())

    t = time.perf_counter()
    for encoded_frame, raw_frame in zip(encoded_frames, raw_frames):
        decoded = decoder.decode(encoded_frame)
        assert raw_frame == decoded
    t = time.perf_counter() - t
    print("TIME", t)
#
if __name__ == "__main__":
    main()