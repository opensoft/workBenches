import socket
import io
import unittest
from unittest.mock import patch,Mock,MagicMock
import proxy

class PublicDestinationTests(unittest.TestCase):
    def handler(self,method,header):
        handler=object.__new__(proxy.Handler)
        handler.connection=Mock();handler.wfile=io.BytesIO()
        handler.rfile=io.BytesIO((method+' http://example.test/update.cab HTTP/1.1\r\n'+header+'\r\n\r\n').encode('ascii'))
        return handler

    def test_empty_download_body_is_allowed_and_header_removed(self):
        for method in ('GET','HEAD'):
            with self.subTest(method=method),patch('proxy.connect_public',return_value=MagicMock()) as connect,patch('proxy.select.select',return_value=([],[],[])):
                handler=self.handler(method,'Content-Length: 0');handler.handle()
                connect.assert_called_once_with('example.test',80)
                sent=connect.return_value.__enter__.return_value.sendall.call_args.args[0]
                self.assertNotIn(b'Content-Length',sent)

    def test_download_bodies_and_transfer_encoding_stay_denied(self):
        for header in ('Content-Length: 1','Content-Length: -1','Content-Length: 00','Transfer-Encoding: chunked'):
            with self.subTest(header=header),patch('proxy.connect_public') as connect:
                handler=self.handler('GET',header);handler.handle()
                connect.assert_not_called();self.assertIn(b'403 Forbidden',handler.wfile.getvalue())

    def address(self,value): return (socket.AF_INET,socket.SOCK_STREAM,6,'',(value,443))
    def test_private_and_special_destinations_never_open_socket(self):
        for address in ('127.0.0.1','192.168.1.1','10.0.0.1','169.254.169.254','0.0.0.0','100.64.0.1'):
            with self.subTest(address=address),patch('proxy.socket.getaddrinfo',return_value=[self.address(address)]),patch('proxy.socket.socket') as opened:
                with self.assertRaises(ValueError): proxy.connect_public('example.test',443)
                opened.assert_not_called()
    def test_mixed_dns_answer_is_rejected(self):
        with patch('proxy.socket.getaddrinfo',return_value=[self.address('8.8.8.8'),self.address('10.0.0.1')]),patch('proxy.socket.socket') as opened:
            with self.assertRaises(ValueError): proxy.connect_public('example.test',443)
            opened.assert_not_called()
    def test_connect_uses_validated_numeric_address(self):
        connection=Mock()
        with patch('proxy.socket.getaddrinfo',return_value=[self.address('8.8.8.8')]),patch('proxy.socket.socket',return_value=connection):
            self.assertIs(proxy.connect_public('example.test',443),connection)
            connection.connect.assert_called_once_with(('8.8.8.8',443))

if __name__=='__main__': unittest.main()
