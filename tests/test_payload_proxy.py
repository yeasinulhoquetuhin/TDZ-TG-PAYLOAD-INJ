#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import importlib.util
import pathlib
import sys
import unittest

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "tdz_payload_proxy.py"
spec = importlib.util.spec_from_file_location("tdz_payload_proxy", MODULE_PATH)
proxy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = proxy
assert spec.loader is not None
spec.loader.exec_module(proxy)


async def echo_handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


class PayloadProxyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.backend = await asyncio.start_server(echo_handler, "127.0.0.1", 0)
        backend_port = self.backend.sockets[0].getsockname()[1]
        self.config = proxy.ProxyConfig(
            bind_host="127.0.0.1",
            public_port=0,
            target_host="127.0.0.1",
            target_port=backend_port,
            header_timeout=1.0,
            max_header_bytes=8192,
            buffer_size=16384,
        )
        self.server = await proxy.create_server(self.config)
        self.proxy_port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self) -> None:
        self.server.close()
        self.backend.close()
        await self.server.wait_closed()
        await self.backend.wait_closed()

    async def connect(self) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        return await asyncio.open_connection("127.0.0.1", self.proxy_port)

    async def test_upgrade_response_and_inline_payload(self) -> None:
        reader, writer = await self.connect()
        payload = b"SSH-2.0-TDZ-Test\r\n"
        writer.write(
            b"GET / HTTP/1.1\r\n"
            b"Host: example.com\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n" + payload
        )
        await writer.drain()
        response = await reader.readuntil(b"\r\n\r\n")
        self.assertEqual(response, proxy.SWITCHING_PROTOCOLS)
        self.assertEqual(await reader.readexactly(len(payload)), payload)
        writer.close()
        await writer.wait_closed()

    async def test_fragmented_header(self) -> None:
        reader, writer = await self.connect()
        writer.write(b"GET / HTTP/1.1\r\nHost: x\r\n")
        await writer.drain()
        await asyncio.sleep(0.02)
        writer.write(b"Connection: Upgrade\r\n\r\nhello")
        await writer.drain()
        await reader.readuntil(b"\r\n\r\n")
        self.assertEqual(await reader.readexactly(5), b"hello")
        writer.close()
        await writer.wait_closed()

    async def test_bidirectional_binary_relay(self) -> None:
        reader, writer = await self.connect()
        data = bytes(range(256)) * 128
        writer.write(b"POST /payload HTTP/1.1\r\nHost: x\r\n\r\n")
        await writer.drain()
        await reader.readuntil(b"\r\n\r\n")
        writer.write(data)
        await writer.drain()
        self.assertEqual(await reader.readexactly(len(data)), data)
        writer.close()
        await writer.wait_closed()

    async def test_concurrent_clients(self) -> None:
        async def one_client(index: int) -> bytes:
            reader, writer = await self.connect()
            data = (f"client-{index}-".encode() * 1024)
            writer.write(b"GET / HTTP/1.1\r\nHost: x\r\n\r\n" + data)
            await writer.drain()
            await reader.readuntil(b"\r\n\r\n")
            echoed = await reader.readexactly(len(data))
            writer.close()
            await writer.wait_closed()
            return echoed

        results = await asyncio.gather(*(one_client(i) for i in range(12)))
        for index, result in enumerate(results):
            self.assertEqual(result, f"client-{index}-".encode() * 1024)

    async def test_incomplete_header_is_closed(self) -> None:
        reader, writer = await self.connect()
        writer.write(b"GET / HTTP/1.1\r\n")
        await writer.drain()
        writer.write_eof()
        self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        writer.close()
        await writer.wait_closed()


class ValidationTests(unittest.TestCase):
    def test_valid_port(self) -> None:
        self.assertEqual(proxy.valid_port("443"), 443)

    def test_invalid_port(self) -> None:
        with self.assertRaises(Exception):
            proxy.valid_port("70000")


if __name__ == "__main__":
    unittest.main(verbosity=2)
