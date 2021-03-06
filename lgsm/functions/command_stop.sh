#!/bin/bash
# LGSM command_stop.sh function
# Author: Daniel Gibbs
# Website: https://gameservermanagers.com
lgsm_version="210516"

# Description: Stops the server.

local modulename="Stopping"
function_selfname="$(basename $(readlink -f "${BASH_SOURCE[0]}"))"

# Attempts Graceful of source using rcon 'quit' command.
fn_stop_graceful_source(){
	fn_print_dots "Graceful: rcon quit"
	fn_scriptlog "Graceful: rcon quit"
	# sends quit
	tmux send -t "${servicename}" quit ENTER > /dev/null 2>&1
	# waits up to 30 seconds giving the server time to shutdown gracefuly
	for seconds in {1..30}; do
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok "Graceful: rcon quit: ${seconds}: "
			fn_print_ok_eol_nl
			fn_scriptlog "Graceful: rcon quit: OK: ${seconds} seconds"
			break
		fi
		sleep 1
		fn_print_dots "Graceful: rcon quit: ${seconds}"
	done
	check_status.sh
	if [ "${status}" != "0" ]; then
		fn_print_fail "Graceful: rcon quit: "
		fn_print_fail_eol_nl
		fn_scriptlog "Graceful: rcon quit: FAIL"
		fn_stop_tmux
	fi
	sleep 1
}

# Attempts Graceful of goldsource using rcon 'quit' command.
# Goldsource 'quit' command restarts rather than shutsdown
# this function will only wait 3 seconds then force a tmux shutdown.
# preventing the server from coming back online.
fn_stop_graceful_goldsource(){
	fn_print_dots "Graceful: rcon quit"
	fn_scriptlog "Graceful: rcon quit"
	# sends quit
	tmux send -t "${servicename}" quit ENTER > /dev/null 2>&1
	# waits 3 seconds as goldsource servers restart with the quit command
	for seconds in {1..3}; do
		sleep 1
		fn_print_dots "Graceful: rcon quit: ${seconds}"
	done
	fn_print_ok "Graceful: rcon quit: ${seconds}: "
	fn_print_ok_eol_nl
	fn_scriptlog "Graceful: rcon quit: OK: ${seconds} seconds"
	sleep 1
	fn_stop_tmux
}

# Attempts Graceful of 7 Days To Die using telnet.
fn_stop_telnet_sdtd(){
	sdtd_telnet_shutdown=$( expect -c '
	proc abort {} {
		puts "Timeout or EOF\n"
		exit 1
	}
	spawn telnet '"${telnetip}"' '"${telnetport}"'
	expect {
		"password:"     { send "'"${telnetpass}"'\r" }
		default         abort
	}
	expect {
		"session."  { send "shutdown\r" }
		default         abort
	}
	expect { eof }
	puts "Completed.\n"
	')
	
}

fn_stop_graceful_sdtd(){
	fn_print_dots "Graceful: telnet"
	fn_scriptlog "Graceful: telnet"
	sleep 1
	if [ "${telnetenabled}" == "false" ]; then
		fn_print_info_nl "Graceful: telnet: DISABLED: Enable in ${servercfg}"
	elif [ "$(command -v expect)" ]||[ "$(which expect >/dev/null 2>&1)" ]; then
		# Tries to shutdown with both localhost and server IP.
		for telnetip in 127.0.0.1 ${ip}; do
			fn_print_dots "Graceful: telnet: ${telnetip}"
			fn_scriptlog "Graceful: telnet: ${telnetip}"
			sleep 1
			fn_stop_telnet_sdtd
			completed=$(echo -en "\n ${sdtd_telnet_shutdown}"|grep "Completed.")
			refused=$(echo -en "\n ${sdtd_telnet_shutdown}"|grep "Timeout or EOF")
			if [ -n "${refused}" ]; then
				fn_print_warn "Graceful: telnet: ${telnetip}: "
				fn_print_fail_eol_nl
				fn_scriptlog "Graceful: telnet: ${telnetip}: FAIL"
				sleep 1
			elif [ -n "${completed}" ]; then
				break
			fi
		done

		# If telnet was successful will use telnet again to check the connection has closed
		# This confirms that the tmux session can now be killed.
		if [ -n "${completed}" ]; then
			for seconds in {1..30}; do
				fn_stop_telnet_sdtd
				refused=$(echo -en "\n ${sdtd_telnet_shutdown}"|grep "Timeout or EOF")
				if [ -n "${refused}" ]; then
					fn_print_ok "Graceful: telnet: ${telnetip}: "
					fn_print_ok_eol_nl
					fn_scriptlog "Graceful: telnet: ${telnetip}: ${seconds} seconds"
					break
				fi
				sleep 1
				fn_print_dots "Graceful: rcon quit: ${seconds}"
			done
		# If telnet failed will go straight to tmux shutdown. 
		# If cannot shutdown correctly world save may be lost
		else
			if [ -n "${refused}" ]; then
				fn_print_fail "Graceful: telnet: "
				fn_print_fail_eol_nl
				fn_scriptlog "Graceful: telnet: ${telnetip}: FAIL"
			else
				fn_print_fail_nl "Graceful: telnet: Unknown error"
				fn_scriptlog "Graceful: telnet: Unknown error"
			fi
			echo -en "\n" | tee -a "${scriptlog}"
			echo -en "Telnet output:" | tee -a "${scriptlog}"
			echo -en "\n ${sdtd_telnet_shutdown}" | tee -a "${scriptlog}"
			echo -en "\n\n" | tee -a "${scriptlog}"
		fi
	else
		fn_print_dots "Graceful: telnet: "
		fn_scriptlog "Graceful: telnet: "
		fn_print_fail "Graceful: telnet: expect not installed: "
		fn_print_fail_eol_nl
		fn_scriptlog "Graceful: telnet: expect not installed: FAIL"
	fi
	sleep 1
	fn_stop_tmux
}

fn_stop_graceful_select(){
	if [ "${gamename}" == "7 Days To Die" ]; then
		fn_stop_graceful_sdtd
	elif [ "${engine}" == "source" ]; then
		fn_stop_graceful_source
	elif [ "${engine}" == "goldsource" ]; then
		fn_stop_graceful_goldsource
	else
		fn_stop_tmux
	fi
}

fn_stop_ark(){
    	MAXPIDITER=15 # The maximum number of times to check if the ark pid has closed gracefully.
        info_config.sh
        if [ -z $queryport ] ; then
                fn_print_warn "no queryport found using info_config.sh"
                userconfigfile="${filesdir}"
                userconfigfile+="/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini"
                queryport=$(grep ^QueryPort= ${userconfigfile} | cut -d= -f2 | sed "s/[^[:digit:].*].*//g")
        fi
        if [ -z $queryport ] ; then
                fn_print_warn "no queryport found in the GameUsersettings.ini file"
                return
        fi

        if [[ ${#queryport} -gt 0 ]] ; then
                for (( pidcheck=0 ; pidcheck < ${MADPIDITER} ; pidcheck++ )) ; do
                        pid=$(netstat -nap 2>/dev/null | grep ^udp[[:space:]] |\
                                grep :${queryport}[[:space:]] | rev | awk '{print $1}' |\
                                rev | cut -d\/ -f1)
                        #
                        # check for a valid pid
                        let pid+=0 # turns an empty string into a valid number, '0',
                        # and a valid numeric pid remains unchanged.
                        if [[ $pid -gt 1 && $pid -le $(cat /proc/sys/kernel/pid_max) ]] ; then
                        fn_print_dots "Process still bound. Awaiting graceful exit: $pidcheck"
                                sleep 1
                        else
                                break # Our job is done here
                        fi # end if for pid range check
                done
                if [[ ${pidcheck} -eq ${MAXPIDITER} ]] ; then
                        # The process doesn't want to close after 20 seconds.
                        # kill it hard.
                        fn_print_warn "Terminating reluctant Ark process: $pid"
                        kill -9 $pid
                fi
        fi # end if for port check
} # end of fn_stop_ark

fn_stop_teamspeak3(){
	fn_print_dots "${servername}"
	fn_scriptlog "${servername}"
	sleep 1
	${filesdir}/ts3server_startscript.sh stop > /dev/null 2>&1
	check_status.sh
	if [ "${status}" == "0" ]; then
		# Remove lock file
		rm -f "${rootdir}/${lockselfname}"
		fn_print_ok_nl "${servername}"
		fn_scriptlog "Stopped ${servername}"
	else
		fn_print_fail_nl "Unable to stop${servername}"
		fn_scriptlog "Unable to stop${servername}"
	fi
}

fn_stop_tmux(){
	fn_print_dots "${servername}"
	fn_scriptlog "tmux kill-session: ${servername}"
	sleep 1
	# Kill tmux session
	tmux kill-session -t "${servicename}" > /dev/null 2>&1
	sleep 0.5
	check_status.sh
	if [ "${status}" == "0" ]; then
		# Remove lock file
		rm -f "${rootdir}/${lockselfname}"
		# ARK doesn't clean up immediately after tmux is killed.
                # Make certain the ports are cleared before continuing.
                if [ "${gamename}" == "ARK: Survivial Evolved" ]; then
                        fn_stop_ark
                        echo -en "\n"
                fi
		fn_print_ok_nl "${servername}"
		fn_scriptlog "Stopped ${servername}"
	else
		fn_print_fail_nl "Unable to stop${servername}"
		fn_scriptlog "Unable to stop${servername}"
	fi
}

# checks if the server is already stopped before trying to stop.
fn_stop_pre_check(){
	if [ "${gamename}" == "Teamspeak 3" ]; then
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok_nl "${servername} is already stopped"
			fn_scriptlog "${servername} is already stopped"
		else
			fn_stop_teamspeak3
		fi
	else
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok_nl "${servername} is already stopped"
			fn_scriptlog "${servername} is already stopped"
		else
			fn_stop_graceful_select
		fi
	fi
}

check.sh
info_config.sh
fn_print_dots "${servername}"
fn_scriptlog "${servername}"
sleep 1
fn_stop_pre_check
