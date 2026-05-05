#!/usr/bin/env bash

data_dir=_local_data
data_file=$data_dir/curl_dump.json

mkdir -pv $data_dir

function follow_all_dumps(){
tail -F _local_data/curl_dump.json /var/www/html/{alt-curl_dump.json,curl_dump.json}
}

while true; do
	#cat $data_file | jq -c '.current.measurement';
	cat $data_file | jq  
       	sleep 60;
       	clear;
done

tail -F _local_data/curl_dump.json /var/www/html/{alt-curl_dump.json,curl_dump.json}
