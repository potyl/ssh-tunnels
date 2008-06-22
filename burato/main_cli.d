/*
 * main_cli.d
 *
 * Copyright (C) 2008 Emmanuel Rodriguez
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

module burato.main_cli;

/**
 * This module provides a command line program that can be used to start new SSH
 * tunnels that are each backed by a corresponding iptable rule.
 *
 * This program is expected to be executed from the command line and provides no
 * graphical interface. It can only accept the tunnels to create at the command
 * line and once it's launched there's no interaction possible with it.
 *
 * To stop the program simply do a CTRL-C or kill the program with any standard
 * signal. This will cause the program to gracefully close all tunnels and to
 * remove the corresponding iptable rules.
 *
 * If an individual tunnel dies or is killed the program should detect it an
 * remove the corresponding iptable rule.
 *
 * NOTE: If the program is killed with the signal "KILL" (9) then no clean will
 *       be made. This means that the iptable rules might still be available.
 */

private import std.stdio;
private import std.process: waitpid;
private import std.string;


private import std.c.linux.linux:
	SIGINT,
	SIGTERM,
	SIGQUIT
;
private import std.c.process: getpid;


private import burato.signal: 
	signal,
	runUninterrupted
;

private import burato.ssh.manager;
private import burato.ssh.connection;
private import burato.network;


/**
 * The tunnels opened so far.
 */
SshManager MANAGER;



/**
 * Main entry point of the program.
 */
int main (string [] args) {

	// Get the command line parameters
	if (args.length <= 2) {
		writefln("Usage: hop port:host...");
		return 1;
	}
	
	// The SSH hopping station
	string hop = args[1];
	
	// Get the addresses (host, port) of the tunnels to create
	NetworkAddress [] addresses;
	for (size_t i = 2; i < args.length; ++i) {
		string arg = args[i];
		string [] parts = split(arg, ":");
		
		if (parts.length != 2) {
			writefln("Ignoring argument %d ('%s') because it has a bad syntax.", i, arg);
			continue;
		}
		
		string host = parts[0];
		ushort port = cast(ushort) atoi(parts[1]);

		addresses.length = addresses.length + 1;
		addresses[addresses.length - 1] = new NetworkAddress(host, port);
	}
	
	
	if (addresses.length == 0) {
		writefln("Couldn't parse a single host:port pair.");
		return 1;
	}

	const int [] signals = [
		SIGINT,
		SIGTERM,
		SIGQUIT,
	];
	
	// Register our own signal handler
	foreach (int sig; signals) {
		signal(sig, &quitSighandler);
	}


	SshManager manager = new SshManager(signals);
	MANAGER = manager;

	SshConnection connection = manager.createSshConnection(hop, addresses);
	manager.waitForTunnelsToDie();
	
	return 0;
}


/**
 * Custom signal handler used to quit the application.
 */
private void quitSighandler (int sig) {
	writefln("Program caught a termination signal. Closing all tunnels.");

	MANAGER.closeSshConnections();
	std.c.stdlib._exit(0);
}
