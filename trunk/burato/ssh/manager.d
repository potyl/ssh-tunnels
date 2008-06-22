/*
 * manager.d - Manages SSH connections.
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

module burato.ssh.manager;

/**
 * This module provides the class Manager which is used to create/delete SSH
 * connections.
 *
 * The class is used for managing SSH tunnels that are paired with iptables
 * rules in order to make TCP/IP connections seem transparent.
 *
 * Usually an application will have a single instance of the Manager. This
 * instance is used to manage the tunnels and to monitor them. The monitoring
 * involves waiting on the PIDs of the SSH processes. Once a PID is dead the
 * manager will harvest the connection and remove the corresponding iptables
 * rules.
 */

private import std.stdio;
private import std.path: expandTilde; 
private import std.process: getpid, waitpid;

private import burato.ssh.config;
private import burato.ssh.connection;
private import burato.ssh.tunnel;
private import burato.network;
private import burato.signal: runUninterrupted;

public class SshManager {
	
	/**
	 * The SSH connections opened so far. Since each SSH connection is binded by a
	 * process the PID is used as a key for retrieving the connection instance.
	 */
	SshConnection [pid_t] connections;
	
	/**
	 * The signal to block during the delicate operations with the SSH tunnels
	 * (creating/closing).
	 */
	int [] signals;	
	

	/**
	 * Creates a new instance.
	 *
	 * A list of signals can be passed to this constructor. These signals will be
	 * blocked while the tunnels are created and reaped. This is done to ensure
	 * that the iptables rules are manipulated properly.
	 */
	public this (int [] signals) {
		if (signals is null) {
			signals = new int [0];
		}
		this.signals = signals;
	}



	/**
	 * Creates an SSH connection that will open the tunnels to the given targets.
	 * 
	 * The connection will be already open and working.
	 */
	public SshConnection createSshConnection (string hop, NetworkAddress [] targetAddresses) {
	
		// Each target address must be paired with a dedicated local port. The best
		// way to do it is to create our selves a TCP/IP socket to the hop and to
		// reuse that port for the SSH tunnel.
		

		// Resolve the real hostname of the SSH hop and the port to use
		NetworkAddress hopAddress = getNetworkAddress(hop);
		writefln("SSH hop is %s", hopAddress);
		

		// Build the tunnel instances that will be managed by this connection. The 
		// tunnels are not yet connected.
		NetworkAddress [] localAddresses = new NetworkAddress [targetAddresses.length];
		SshTunnel [] tunnels = new SshTunnel[targetAddresses.length];
		
		foreach (int i, NetworkAddress targetAddress; targetAddresses) {
			// Find a free local port to use
			NetworkAddress localAddress = getLocalAddressForRemoteConnection(hopAddress);
			
			// Prepare a tunnel instance (nothing is binded yet!)
			SshTunnel tunnel = new SshTunnel(localAddress, targetAddress);
			tunnels[i] = tunnel;
		}
		
		// Create and bind the SSH connection
		SshConnection connection;
		void openConnection () {
			connection = new SshConnection(hop, tunnels);
			pid_t pid = connection.connect();
			this.connections[pid] = connection;
		}
		runUninterrupted(&openConnection, this.signals);
		
		return connection;
	}
	

	/**
	 * Waits for the tunnels to die. The tunnels will usually not die on their
	 * own, but if a tunnel (the SSH process) is killed then a reaper will remove
	 * the corresponding iptables rules created for each SSH tunnel.
	 */
	public void waitForTunnelsToDie () {

		// Wait for the tunnels to resume
		writefln("Waiting for childs: %s from %d", this.connections.keys, getpid());
		while (this.connections.length > 0) {
			
			// Wait for a tunnel to die
			int status;
			pid_t pid = waitpid(-1, &status, 0);
			
			// Delegate used to close the tunnel
			void closeConnection () {
			
				writefln("Child PID %d has resumed with status: %d", pid, status);
				writefln("stopped    = %s", stopped(status));
				writefln("signaled   = %s", signaled(status));
				writefln("exited     = %s", exited(status));
				writefln("exitstatus = %d", exitstatus(status));
				writefln("termsig    = %d", termsig(status));

				// Find out which tunnel died
				SshConnection *pointer = (pid in this.connections);
				if (pointer is null) {return;}
				this.connections.remove(pid);

				// Close the SSH tunnel
				SshConnection connection = *pointer;
				connection.disconnect();
			};

			runUninterrupted(&closeConnection, signals);
		}
	}
	

	/**
	 * Closes all connections.
	 */
	public void closeSshConnections () {
		foreach (pid_t pid, SshConnection connection; this.connections) {
			connection.disconnect();
//			this.connections.remove(pid);
		}
	}
	
	
	/**
	 * Removes the SSH connection that's backed by the given PID and returns it.
	 * If there's no SSH connection that's using the given PID then null will be
	 * returned.
	 */
	public SshConnection removeSshConnection (pid_t pid) {
		// Make sure that there's a connection with that PID
		SshConnection *pointer = (pid in this.connections);
		if (pointer is null) {
			return null;
		}
		SshConnection connection = *pointer;
		
		// Remove it from the hash
		this.connections.remove(pid);
		
		return connection;
	}
}


/**
 * Finds the NetworkAddress (real hostname and port) of the the given host. This
 * function is needed because the host is in the same format as OpenSSH expects
 * its hosts. In fact the host used by OpenSSH can also be an alias that will be
 * latter resolved to a valid host name. Futhermore, the host might be using a
 * different port. Also the host is allowed to have an user name. For instance,
 * the following host: "root@mailserver" is valid.
 *
 * If the host can't be found then "null" will be returned.
 */
private NetworkAddress getNetworkAddress (string host) {
	
	string [] files = [
		expandTilde("~/.ssh/config"),
		"/etc/ssh/ssh_config",
	];

	foreach (string file; files) {
		NetworkAddress address = burato.ssh.config.getNetworkAddress(host, file);
		if (address !is null) {
			return address;
		}
	}

	return null;
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
