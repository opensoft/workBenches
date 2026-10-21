import socket
import unittest
from unittest.mock import patch,Mock
import proxy

class PublicDestinationTests(unittest.TestCase):
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
