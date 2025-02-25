from ectf25.utils.decoder import DecoderIntf
from ectf25_design.gen_subscription import gen_subscription
from ectf25_design.encoder import Encoder
import random
import time

def main():
    secrets = open('global.secrets', 'rb').read()

    channel = 1

    raw_frames = [random.randbytes(64) for _ in range(10_000)]

    encoder = Encoder(secrets=secrets)

    t = time.perf_counter()
    for (i, frame) in enumerate(raw_frames):
        encoder.encode(channel=channel, frame=frame, timestamp=i)
    t = time.perf_counter() - t
    print("FRAMES", len(raw_frames))
    print("TIME  ", t)
    print("FPS   ", len(raw_frames) / t)

if __name__ == "__main__":
    main()
