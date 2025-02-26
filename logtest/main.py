from pathlib import Path
from ectf25.utils.decoder import DecoderIntf, Message, logger
import argparse
import re
import ast
from base64 import b64decode
import zlib
from dataclasses import dataclass
from abc import ABC


@dataclass
class Command(ABC):
    pass


@dataclass
class SendPacket(Command):
    packet: bytes


@dataclass
class GetMessage(Command):
    pass


@dataclass
class Log(Command):
    message: str


# def get_data(html: str) -> str:
#     chunks_str = next(re.finditer(r"let chunks = (\[[^\]]*\])", html))[1]
#     print(chunks_str)
#     data = b"".join(b64decode(chunk) for chunk in ast.literal_eval(chunks_str))
#     return zlib.decompress(data).decode()
#     # print(chunks)


def get_commands(terminal_output: str) -> list[Command]:
    commands = []
    lines = terminal_output.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("#"):
            continue
        if match := re.search(r"""Sending packet (b'.*'|b".*")$""", line):
            commands.append(SendPacket(ast.literal_eval(match[1])))
        elif match := re.search(r"Got message Message\(opcode=<Opcode.(\w+)", line):
            opcode = match[1]
            if opcode != "DEBUG" and opcode != "ERROR":
                commands.append(GetMessage())
        elif (
            "================================================================================"
            in line
        ):
            commands.append(Log("\n".join(lines[i : i + 7])))

    return commands


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("terminal_output")
    parser.add_argument("port")
    args = parser.parse_args()
    terminal_output = Path(args.terminal_output).read_text()
    port = args.port

    commands = get_commands(terminal_output)

    decoder = DecoderIntf(port)
    decoder._open()
    i = 0
    while i <= len(commands):
        match commands[i]:
            case SendPacket(packet):
                logger.debug(f"Sending packet {packet}")
                decoder.ser.write(packet)
                decoder.get_msg()
            case Log(message):
                print(message)
            case GetMessage():
                print("Starting getmessage")
                try:
                    message = decoder.get_msg()
                except Exception:
                    pass
        i += 1


if __name__ == "__main__":
    main()
