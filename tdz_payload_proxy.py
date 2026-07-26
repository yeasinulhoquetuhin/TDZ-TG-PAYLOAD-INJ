#!/usr/bin/env python3
"""TDZ Payload Proxy.

A small HTTP Upgrade tunnel: it accepts an HTTP-style payload header,
returns a WebSocket-style 101 response, then relays raw TCP bytes to one
fixed local backend port.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import logging
import signal
import socket
from dataclasses import dataclass
from typing import Optional

HTTP_HEADER_END = b"\r\n\r\n"
SWITCHING_PROTOCOLS = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"\r\n"
)


@dataclass(frozen=True)
class ProxyConfig:
    bind_host: str = "0.0.0.0"
    public_port: int = 8080
    target_host: str = "127.0.0.1"
    target_port: int = 22
    header_timeout: float = 8.0
    max_header_bytes: int = 65536
    buffer_size: int = 65536


def configure_socket(writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    if sock is None:
        return
    with contextlib.suppress(OSError):
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    with contextlib.suppress(OSError):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)


async def read_payload_header(
    reader: asyncio.StreamReader,
    *,
    timeout: float,
    max_bytes: int,
) -> tuple[bytes, bytes]:
    """Return (header, bytes already received after the header)."""
    data = bytearray()
    while True:
        marker = data.find(HTTP_HEADER_END)
        if marker >= 0:
            split_at = marker + len(HTTP_HEADER_END)
            return bytes(data[:split_at]), bytes(data[split_at:])
        if len(data) >= max_bytes:
            raise ValueError("payload header exceeds configured limit")
        read_size = min(4096, max_bytes - len(data))
        chunk = await asyncio.wait_for(reader.read(read_size), timeout=timeout)
        if not chunk:
            raise ConnectionError("client disconnected before header completed")
        data.extend(chunk)


async def relay(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    *,
    buffer_size: int,
) -> None:
    try:
        while True:
            chunk = await reader.read(buffer_size)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        with contextlib.suppress(Exception):
            writer.write_eof()
            await writer.drain()


async def close_writer(writer: Optional[asyncio.StreamWriter]) -> None:
    if writer is None:
        return
    writer.close()
    with contextlib.suppress(Exception):
        await writer.wait_closed()


async def handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    config: ProxyConfig,
) -> None:
    peer = writer.get_extra_info("peername")
    target_writer: Optional[asyncio.StreamWriter] = None
    configure_socket(writer)

    try:
        _header, pending = await read_payload_header(
            reader,
            timeout=config.header_timeout,
            max_bytes=config.max_header_bytes,
        )

        target_reader, target_writer = await asyncio.open_connection(
            config.target_host,
            config.target_port,
        )
        configure_socket(target_writer)

        writer.write(SWITCHING_PROTOCOLS)
        await writer.drain()

        if pending:
            target_writer.write(pending)
            await target_writer.drain()

        client_to_target = asyncio.create_task(
            relay(reader, target_writer, buffer_size=config.buffer_size)
        )
        target_to_client = asyncio.create_task(
            relay(target_reader, writer, buffer_size=config.buffer_size)
        )

        done, pending_tasks = await asyncio.wait(
            {client_to_target, target_to_client},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending_tasks:
            task.cancel()
        await asyncio.gather(*done, *pending_tasks, return_exceptions=True)
    except (asyncio.TimeoutError, ConnectionError, ValueError, OSError) as exc:
        logging.debug("connection %r closed: %s", peer, exc)
    except Exception:
        logging.exception("unexpected proxy error for %r", peer)
    finally:
        await close_writer(target_writer)
        await close_writer(writer)


async def create_server(config: ProxyConfig) -> asyncio.AbstractServer:
    return await asyncio.start_server(
        lambda reader, writer: handle_client(reader, writer, config),
        config.bind_host,
        config.public_port,
        backlog=512,
        reuse_address=True,
        limit=config.max_header_bytes + config.buffer_size,
    )


async def run(config: ProxyConfig) -> None:
    server = await create_server(config)
    sockets = server.sockets or []
    addresses = ", ".join(str(sock.getsockname()) for sock in sockets)
    logging.info(
        "TDZ Payload Proxy listening on %s -> %s:%s",
        addresses,
        config.target_host,
        config.target_port,
    )

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(sig, stop_event.set)

    async with server:
        await stop_event.wait()


def valid_port(value: str) -> int:
    try:
        port = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("port must be a number") from exc
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1 and 65535")
    return port


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TDZ HTTP payload tunnel")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--public-port", required=True, type=valid_port)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", required=True, type=valid_port)
    parser.add_argument("--header-timeout", type=float, default=8.0)
    parser.add_argument("--max-header-bytes", type=int, default=65536)
    parser.add_argument("--buffer-size", type=int, default=65536)
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    config = ProxyConfig(
        bind_host=args.bind,
        public_port=args.public_port,
        target_host=args.target_host,
        target_port=args.target_port,
        header_timeout=max(1.0, args.header_timeout),
        max_header_bytes=max(4096, args.max_header_bytes),
        buffer_size=max(4096, args.buffer_size),
    )
    try:
        asyncio.run(run(config))
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
