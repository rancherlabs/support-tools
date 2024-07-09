#!/usr/bin/env python3
import json
import petname
import os
import re
import socket
import sys
#TODO implement logging

def load_mapping(mapping_file):
    if os.path.exists(mapping_file):
        with open(mapping_file, 'r') as file:
            return json.load(file)
    return {}

def save_mapping(mapping, mapping_file):
    with open(mapping_file, 'w') as file:
        json.dump(mapping, file, indent=2)

def extract_hostnames(text):
    # Regular expression to match fqdn hostnames
    hostname_regex = re.compile(r'\b(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\b')
    return set(hostname_regex.findall(text))

def extract_ip_addresses(text):
    # Regular expression to match IP addresses
    ip_regex = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')
    return set(ip_regex.findall(text))

def obfuscate_subdomain(subdomain, mapping):
    if subdomain not in mapping:
        #print('subdomain passed in: ' + subdomain)
        # TODO check for collisions
        return petname.Generate(1)
    else:
        #print('subdomain found: ' + str(subdomain))
        return mapping[subdomain]

def obfuscate_hostname(hostname, mapping):
    subdomains = hostname.split('.')
    #print('subdomains: ' + str(subdomains))
    obfuscated_subdomains = [obfuscate_subdomain(sub, mapping) for sub in subdomains]
    obfuscated_hostname = '.'.join(obfuscated_subdomains)
    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_host(hostname, mapping):
    obfuscated_hostname = obfuscate_subdomain(hostname, mapping)
    #print('debug obf hostname:' + obfuscated_hostname)
    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_ip_address(ip_address, ip_mapping):
    octets = ip_address.split('.')
    if ip_address not in ip_mapping:
        obfuscated_octets = [octets[0]] + [petname.Generate(1) for _ in octets[1:]]
        ip_mapping[ip_address] = '.'.join(obfuscated_octets)
    return ip_mapping[ip_address]

def obfuscate_text(text, hostname_mapping, ip_mapping):
    hostnames = extract_hostnames(text)
    ip_addresses = extract_ip_addresses(text)
    short_hostname = socket.gethostname()

    for hostname in hostnames:
        #print("processing hostname:" + hostname)
        if hostname not in hostname_mapping:
            #print('hostname not in map. hostname: ' + hostname)
            obfuscated_name = obfuscate_hostname(hostname, hostname_mapping)
            #print('new obfuscated name: ' + obfuscated_name)
        else:
            obfuscated_name = hostname_mapping[hostname]
            #print("found obfuscated name:" + obfuscated_name)
        text = text.replace(hostname, obfuscated_name)

    for ip_address in ip_addresses:
        if ip_address not in ip_mapping:
            obfuscated_ip = obfuscate_ip_address(ip_address, ip_mapping)
        else:
            obfuscated_ip = ip_mapping[ip_address]
        text = text.replace(ip_address, obfuscated_ip)

    #search for hostname not fqdn
    if short_hostname not in hostname_mapping:
        #print("short_hostname not found. short hostname:" + short_hostname)
        obfuscated_name = obfuscate_host(short_hostname, hostname_mapping)
    else:
        #print("short hostname found")
        obfuscated_name = hostname_mapping[short_hostname]
    text = text.replace(short_hostname, obfuscated_name)

    return text

def process_file(input_file, output_file, hostname_mapping_file='hostname_mapping.json', ip_mapping_file='ip_mapping.json'):
    hostname_mapping = load_mapping(hostname_mapping_file)
    ip_mapping = load_mapping(ip_mapping_file)
    short_hostname = socket.gethostname()

    try:
        with open(input_file, 'r') as file:
            text = file.read()

        obfuscated_text = obfuscate_text(text, hostname_mapping, ip_mapping)

        with open(output_file, 'w') as file:
            file.write(obfuscated_text)

        save_mapping(hostname_mapping, hostname_mapping_file)
        save_mapping(ip_mapping, ip_mapping_file)
    except UnicodeDecodeError:
        pass

if __name__ == "__main__":
  #input_file = sys.argv[1]
  #output_file = sys.argv[2]
  directory = sys.argv[1]

  process_list = ["ipaddrshow","ipneighbour","iproute","ipv6addrshow","ipv6neighbour","ipv6route","nft_ruleset","ss4apn","ss6apn","ssanp","ssitan","sstunlp4","sstunlp6","ssuapn","sswapn","ssxapn","systemd-resolved","hostnamefqdn","iostathx","lsof","uname","hostname","pidstatx","ssitan","syslog","dockerinfo","docker","containerd","cloud-init","sar"]
  #process_list = ["ipaddrshow","ipneighbour","iproute","ipv6addrshow","ipv6neighbour","ipv6route","nft_ruleset","ss4apn","ss6apn","ssanp","ssitan","sstunlp4","sstunlp6","ssuapn","sswapn","ssxapn","systemd-resolved","hostnamefqdn","iostathx","uname","hostname","pidstatx","ssitan"]

  input_file = []
  output_file = []

  map_file = "ip_map.json"
  # iterate over files in directory passed in
  # that are in the process_list. we need a manual override list
  for root, dirs, files in os.walk(directory):
    for filename in files:
      input_file = os.path.join(root, filename)
      tmp_output_file = 'obf_' + filename
      output_file = os.path.join(root, tmp_output_file)
      if filename in process_list:
        print("processing file: " + str(filename))
        process_file(input_file, output_file)
        os.remove(input_file)
        os.rename(output_file, input_file)
