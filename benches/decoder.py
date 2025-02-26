from ectf25.utils.decoder import DecoderIntf
from ectf25_design.gen_subscription import gen_subscription
from ectf25_design.encoder import Encoder
import argparse
import random
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    args = parser.parse_args()

    decoder = DecoderIntf(args.port)

    secrets = open('global.secrets', 'rb').read()

    channel = 1
    decoder.subscribe(gen_subscription(secrets=secrets, device_id=0xdeadbeef, start=1, end=2**64 - 2, channel=channel))

    raw_frames = [random.randbytes(64) for _ in range(100)]

    # Encode all the frames before starting the timer
    encoder = Encoder(secrets=secrets)
    encoded_frames = [encoder.encode(channel=channel, frame=frame, timestamp=(i+1)*1000) for (i, frame) in enumerate(raw_frames)]

    t = time.perf_counter()
    for (raw_frame, encoded_frame) in zip(raw_frames, encoded_frames):
        if decoder.decode(encoded_frame) != raw_frame:
            print("ERROR")
            return
    t = time.perf_counter() - t
    print("FRAMES", len(raw_frames))
    print("TIME  ", t)
    print("FPS   ", len(raw_frames) / t)

if __name__ == "__main__":
    main()
