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
private import std.string: format;

private import burato.ssh.config;
private import burato.ssh.connection;
private import burato.ssh.tunnel;
private import burato.network;
private import burato.signal: runUninterrupted;

private import glib.Timeout;

private const int WNOHANG = 1;

public class SshManager {
	
	/**
	 * Inner class used to pass arguments to a C callback.
	 */
	private class CallbackArgs {
		/**
		 * Instance that's will be invoked during the callback.
		 */
		//SshManager object;
		bool delegate (gpointer) dg;
		
		/**
		 * Arguments to pass to the callback.
		 */
		gpointer arg;
		this (bool delegate (gpointer) dg, gpointer arg) {
			this.dg = dg;
			this.arg = arg;
		}
	};
	
	
	void delegate(SshConnection) [] onCloseCallbacks;
	void delegate(SshConnection) [] onCreateCallbacks;
	
	
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
	 * ID of the timeout used to monitor the SSH processes. If there's no timeout
	 * then 0 will be set as the value.
	 */
	private guint timeout = 0;
	

	/**
	 * Creates a new instance.
	 *
	 * A list of signals can be passed to this constructor. These signals will be
	 * blocked while the tunnels are created and reaped. This is done to ensure
	 * that the iptables rules are manipulated properly.
	 */
	public this (int [] signals) {
		this.signals = signals is null ? new int [0] : signals;
	}
	
	
	/**
	 * Registers a callback that will be invoked each time that an SSH connection
	 * is created.
	 *
	 * The callback will received as parameters the SshConnection that was
	 * created.
	 */
	public void addOnCreateCallback (void delegate(SshConnection) callback) {
		if (callback !is null) {
			this.onCreateCallbacks ~= callback;
		}
	}
	
	
	/**
	 * Registers a callback that will be invoked each time that an SSH connection
	 * is closed.
	 *
	 * The callback will received as parameters the SshConnection being closed.
	 */
	public void addOnCloseCallback (void delegate(SshConnection) callback) {
		if (callback !is null) {
			this.onCloseCallbacks ~= callback;
		}
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
		

		// Build the tunnel instances that will be managed by this connection. The 
		// tunnels are not yet connected.
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
		
		writefln(
			"%s:%d > Created an SSH connection to %s (PID: %d) with %d tunnels",
			__FILE__, __LINE__,
			connection.hop,
			connection.pid,
			connection.tunnels.length
		);

		// Notify the callbacks that a tunnel has been created.
		foreach (int i, void delegate(SshConnection connection) callback; this.onCreateCallbacks) {
			writefln("%s:%d > SSH process %d created, calling callback %d", __FILE__, __LINE__, connection.pid, i);
			callback(connection);
		}
		
		// Creates a periodic check that's used to monitor the SSH connections 
		if (! this.timeout) {
			CallbackArgs args = new CallbackArgs(&this.onTimeout, null);
			this.timeout = Timeout.addSeconds(
				1, 
				cast(GSourceFunc) &onTimeoutCallback, 
				cast(gpointer)args
			);
		}

		return connection;
	}
	

	/**
	 * Waits for the tunnels to die. The tunnels will usually not die on their
	 * own, but if a tunnel (the SSH process) is killed then a reaper will remove
	 * the corresponding iptables rules created for each SSH tunnel.
	 */
	public void waitForTunnelsToDie () {

		// Wait for the SSH processes to resume
		writefln("Waiting for childs: %s from %d", this.connections.keys, getpid());
		while (this.connections.length > 0) {
			
			// Wait for a process to finish (usually by being killed)
			int status;
			pid_t pid = waitpid(-1, &status, 0);
			// Make sure that the process died, waitpid can return when the process is
			// being traced (ptrace) thus still alive
			if (signaled(status) || exited(status)) {
				// Remove the SSH connection (remove the iptables rules)
				this.removeSshConnection(pid);
			}
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

		// Find the SSH connection that's backed by the given PID
		SshConnection *pointer = (pid in this.connections);
		if (pointer is null) {
			return null;
		}
		SshConnection connection = *pointer;
		
		writefln(
			"%s:%d > Removing the SSH connection to %s (PID: %d) with %d tunnels",
			__FILE__, __LINE__,
			connection.hop,
			connection.pid,
			connection.tunnels.length
		);


		// Close the tunnel (interruptions through a kill are forbidden)
		void closeConnection () {
			connection.disconnect();
		};
		runUninterrupted(&closeConnection, this.signals);


		// Remove then entry from the hash
		this.connections.remove(pid);
		
		return connection;
	}
	
	
	/**
	 * This is the callback passed to glib when requesting a timeout. If we don't
	 * pass and extern (C) function the program will crash. The problem is that
	 * passing an extern (C) function is not too D-ish, thus this function acts as
	 * bridge between a delegate and glib.
	 *
	 * The argument is expected to be an instance of CallbackArgs which
	 * encapsulates a delegate and it's argument.
	 */
	extern (C) private static gboolean onTimeoutCallback (gpointer data) {
		CallbackArgs callbackArgs = cast(CallbackArgs) data;
		return callbackArgs.dg(callbackArgs.arg);
	}

	
	/**
	 * Glib timeout called to monitor the SSH processes. The ideal would be to use
	 * the signal CHLD, the problem is that this interferes with the function
	 * "system". Using a glib timeout is not the best as it will wake up the
	 * application on a periodic basis but it's the best that can be done.
	 */
	private bool onTimeout (gpointer data) {
		
		// Check the status of each process without blocking (this has to be quick)
		foreach (pid_t pid, SshConnection connection; this.connections) {

			// Wait for a process to finish (usually by being killed)
			int status;
			pid_t pid_got = waitpid(pid, &status, WNOHANG);

			if (pid_got == 0) {
				// The process is still alive, there's nothing to do
				continue;
			}
			else if (pid_got != pid) {
				writefln(
					"%s:%d > ERROR waited for pid %d and got an answer for pid %d",
					__FILE__, __LINE__,
					pid, pid_got
				);
			}

			// Make sure that the process died, waitpid can return when the process is
			// being traced (ptrace) thus still alive
			if (signaled(status) || exited(status)) {
				// Remove the SSH connection since the SSH process died
				writefln("%s:%d > SSH process %d resumed", __FILE__, __LINE__, pid);
				this.removeSshConnection(pid);



				// Notify the callbacks that a tunnel has been closed.
				foreach (int i, void delegate(SshConnection connection) callback; this.onCloseCallbacks) {
					writefln("%s:%d > SSH process %d resumed, calling callback %d", __FILE__, __LINE__, pid, i);
					callback(connection);
				}
			}
		}


		// Disable the timeout if there's nothing more to monitor
		if (this.connections.length == 0) {
			this.timeout = 0;
			return false;
		}
		

		return true;
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

	bool signaled (int status) {
		return cast(bool)((cast(char)((status & 0x7f) + 1) >> 1) > 0);
	}

	bool exited (int status) {
		return cast(bool)((status & 0x7f) == 0);
	}
}
