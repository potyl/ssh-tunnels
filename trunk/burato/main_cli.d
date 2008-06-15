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

private import burato.tunnel;


/**
 * The tunnels opened so far.
 */
Tunnel [pid_t] TUNNELS;



/**
 * Main entry point of the program.
 */
int main (string [] args) {

	// Get the command line parameters
	if (args.length <= 2) {
		writefln("Usage: hop port:host...");
		return 1;
	}
	string hop = args[1];
writefln("args: %d", args.length);	
	NetworkAddress [] addresses;// = new NetworkAddress[args.length - 2];
	for (size_t i = 2; i < args.length; ++i) {
		string arg = args[i];
		string [] parts = split(arg, ":");
		
		if (parts.length != 2) {
			writefln("Ignoring argument %d ('%s') because it has a bad syntax.", i, arg);
			continue;
		}
		
		writefln("arg %d %s", i, arg);
		
		string host = parts[0];
		ushort port = cast(ushort) atoi(parts[1]);

		addresses.length = addresses.length + 1;
		addresses[addresses.length - 1] = new NetworkAddress(host, port);
	}
	
	
	if (addresses.length == 0) {
		writefln("Couldn't parse a single host:port pair.");
		return 1;
	}
	
	return 0;
	
	ushort port = cast(ushort) atoi(args[2]);
	string [] hosts = args[3 .. args.length];
	
	
	const int [] signals = [
		SIGINT,
		SIGTERM,
		SIGQUIT,
	];
	
	// Register our own signal handler
	foreach (int sig; signals) {
		signal(sig, &quitSighandler);
	}

	createTunnels(hop, port, hosts, signals);
	
	waitForTunnels(signals);
	
	return 0;
}


/**
 * Creates the tunnels to the given hosts/port by using the given hop.
 * @deprecated use createTunnels (string hop, NetworkAddress [] addresses, int [] signals)
 */
private void createTunnels (string hop, ushort port, string [] hosts, int [] signals) {

	foreach (string host; hosts) {
	
		// Create the tunnel
		// FIXME This is little bit overkill since OpenSSH is able to forward
		//       multiple ports with one connection. Here it would be trully nice
		//       to do the same wrap all tunnels through the same hop within a
		//       single OpenSSH connection.

		Tunnel tunnel = new Tunnel(hop, host, port);
		writefln("Creating %s", tunnel);

		// Open the tunnel, make sure to keep it in order to close it latter
		void openTunnel() {
			pid_t pid = tunnel.connect();
			TUNNELS[pid] = tunnel;
		};
		runUninterrupted(&openTunnel, signals);
	}
}


/**
 * Creates the tunnels to the given hosts/port by using the given hop.
 */
private void createTunnels (string hop, NetworkAddress [] addresses, int [] signals) {

	// Open a single tunnel through the same hop
	Tunnel tunnel = new Tunnel(hop, addresses);

	// Open the tunnel, make sure to keep it in order to close it latter
	void openTunnel() {
		pid_t pid = tunnel.connect();
		TUNNELS[pid] = tunnel;
	};
	runUninterrupted(&openTunnel, signals);
}


/**
 * Waits for the tunnels to finish.
 */
private void waitForTunnels (int [] signals) {

	// Wait for the tunnels to resume
	writefln("Waiting for childs: %s from %d", TUNNELS.keys, getpid());
	while (TUNNELS.length > 0) {
		
		// Wait for a tunnel to die
		int status;
		pid_t pid = waitpid(-1, &status, 0);
		
		// Delegate used to close the tunnel
		void closeTunel() {
		
			writefln("Child PID %d has resumed with status: %d", pid, status);
			writefln("stopped    = %s", stopped(status));
			writefln("signaled   = %s", signaled(status));
			writefln("exited     = %s", exited(status));
			writefln("exitstatus = %d", exitstatus(status));
			writefln("termsig    = %d", termsig(status));

			// Find out which tunnel died
			Tunnel *pointer = (pid in TUNNELS);
			if (pointer is null) {
				return;
			}
			TUNNELS.remove(pid);

			Tunnel tunnel = *pointer;
			tunnel.disconnect();
		};

		runUninterrupted(&closeTunel, signals);
	}
}


/**
 * Custom signal handler used to quit the application.
 */
private void quitSighandler (int sig) {
	writefln("Program caught a termination signal. Closing all tunnels.");

	foreach (Tunnel tunnel; TUNNELS) {
		writefln("Closing tunnel %s", tunnel);
		tunnel.disconnect();
	}
	std.c.stdlib._exit(0);
}


// Stolen from std.process
private {

	bool stopped (int status) {
		return cast(bool)((status & 0xff) == 0x7f);
	}

	bool signaled(int status) {
		return cast(bool)((cast(char)((status & 0x7f) + 1) >> 1) > 0);
	}

	int  termsig (int status) {
		return status & 0x7f;
	}

	bool exited (int status) {
		return cast(bool)((status & 0x7f) == 0);
	}

	int  exitstatus (int status) {
		return (status & 0xff00) >> 8;
	}
}
