"""Offline country lookup using DB-IP Lite (CC BY 4.0, https://db-ip.com)."""
import bisect
import csv
import gzip
import ipaddress
import socket
import sys


class CountryLookup:
    def __init__(self, path):
        self.ranges = {4: ([], [], []), 6: ([], [], [])}
        if not path.is_file():
            return
        with gzip.open(path, 'rt', encoding='utf-8', newline='') as source:
            for first, last, country in csv.reader(source):
                version = 6 if ':' in first else 4
                if version != (6 if ':' in last else 4):
                    raise ValueError('Invalid country database range')
                family = socket.AF_INET6 if version == 6 else socket.AF_INET
                try:
                    start = int.from_bytes(socket.inet_pton(family, first), 'big')
                    end = int.from_bytes(socket.inet_pton(family, last), 'big')
                except OSError as error:
                    raise ValueError('Invalid country database address') from error
                if start > end:
                    raise ValueError('Invalid country database range')
                starts, ends, countries = self.ranges[version]
                if starts and start <= ends[-1]:
                    raise ValueError('Unsorted country database')
                starts.append(start)
                ends.append(end)
                countries.append(sys.intern(country) if len(country) == 2 and country.isalpha() else 'ZZ')

    def country(self, address):
        try:
            ip = ipaddress.ip_address(address)
        except ValueError:
            return 'ZZ'
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if not ip.is_global:
            return 'ZZ'
        starts, ends, countries = self.ranges[ip.version]
        index = bisect.bisect_right(starts, int(ip)) - 1
        return countries[index] if index >= 0 and int(ip) <= ends[index] else 'ZZ'
