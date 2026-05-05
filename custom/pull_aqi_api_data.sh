#!/usr/bin/env bash

data_dir=_local_data
data_tmp=$data_dir/curl_dump.tmp
data_file=$data_dir/curl_dump.json
web_root=/var/www/html/
mkdir -pv $data_dir

function pull_record(){
curl -s localhost:8000/api/now/ | jq '.current' 
}

echo " - data being saved to $data_file"
if [[ "$1" != "show" ]] ; then
	echo " - monitor with ./follow_api_curl_dump.sh"
fi

[[ ! -e $data_tmp ]] && touch $data_tmp

while true; do
	if [[ "$1" == "show" ]] ; then
		pull_record | tee -a $data_tmp;
	else
		pull_record >> $data_tmp;
	fi
	jq -s < $data_tmp > $data_file
	sudo cp $data_file $web_root/alt-curl_dump.json
	sudo cp $data_file $web_root

	sleep $((RANDOM/1000+RANDOM/1000));
done
