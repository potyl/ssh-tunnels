/*
 * tunnel.d
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

module burato.tunnel;

/**
 * This module provides the class Tunnel which is used to wrap an SSH tunnel
 * with a custom iptable rule.
 *
 * This class implements an SSH tunnel that's backed by an iptables rule used to
 * redirect the connections to the target host through it's usual port through
 * the local tunnel by using the local port.
 */
 
private import std.stdio: writefln;
private import std.string: format;
private import std.process: execvp, system;
private import std.socket;
private import std.path: expandTilde;

private import std.c.process: getpid;
private import std.c.linux.linux;

private import burato.signal: signalsUnblock;
private import burato.fork: forkTask, pid_t;
private import burato.error: FormattedException, ErrnoException;
private import burato.ssh_config: getNetworkAddress;
private import burato.network: getLocalAddress, NetworkAddress;

private const int [] SIGNALS = [
	SIGHUP,
	SIGINT,
	SIGQUIT,
	SIGILL,
	SIGTRAP,
	SIGABRT,
	SIGIOT,
	SIGBUS,
	SIGFPE,
	SIGKILL,
	SIGUSR1,
	SIGSEGV,
	SIGUSR2,
	SIGPIPE,
	SIGALRM,
	SIGTERM,
	SIGSTKFLT,
	SIGCHLD,
	SIGCONT,
	SIGSTOP,
	SIGTSTP,
	SIGTTIN,
	SIGTTOU,
	SIGURG,
	SIGXCPU,
	SIGXFSZ,
	SIGVTALRM,
	SIGPROF,
	SIGWINCH,
	SIGPOLL,
	SIGIO,
	SIGPWR,
	SIGSYS,
];



/**
 * Representation of an SSH tunnel. A tunnel is backed by an SSH process. For
 * the moment an tunnel requires a dedicated SSH connection and different
 * tunnels, even for the same targets, have to be made through different SSH
 * connections.
 */
class Tunnel {
	
	pid_t pid;
	string hop;

	NetworkAddress local;
	NetworkAddress target;

	
	/**
	 * Creates a new Tunnel instance. This tunnel is not yet connected, this has
	 * to be performed through the method "connect".
	 */
	this(string hop, string localHost, ushort localPort, string targetHost, ushort targetPort) {
		this.pid = 0;
		this.hop = hop;
		this.local = new NetworkAddress(localHost, localPort);
		this.target = new NetworkAddress(targetHost, targetPort);
	}

	
	/**
	 * Creates a new Tunnel instance. This tunnel is not yet connected, this has
	 * to be performed through the method "connect". Furthermore, the local port
	 * and local address to use will be found automatically.
	 */
	this(string hop, string host, ushort port) {
		
		// Resolve the real hostname of the SSH hop and the port to use
		NetworkAddress address = getNetworkAddress(hop);
		
		// Find a free local port to use
		InternetAddress intAddress = getLocalAddress(address);
		
		// Create the instance
		this(hop, intAddress.toAddrString(), intAddress.port, host, port);
	}
	
	
	/**
	 * Connects the tunnel by creating an SSH tunnel and creating the
	 * corresponding iptables rule.
	 */
	pid_t connect () {
		// Create the SSH tunnel
		this.pid = forkTask(&this.createSSHConnection);
		
		// Create the iptable rule
		this.doIpTableRule("-A");
		
		return this.pid;
	}

	
	/**
	 * Disconnects the tunnel by closing the SSH tunnel and removing the
	 * corresponding iptables rule.
	 */
	void disconnect () {

		// Kill the SSH tunnel
writefln("Tunnel >> disconnect >> kill %d", this.pid);
		kill(this.pid, SIGTERM);
		
		// Delete the iptable rule
writefln("Tunnel >> disconnect >> doIpTableRule -D");
		this.doIpTableRule("-D");
	}


	/**
	 * Creates an SSH connection that will open a tunnel to the target.
	 */
	private void createSSHConnection () {
		
		// The string used to tell SSH what tunnel to create
		string tunnel = format("%d:%s:%d", 
			this.local.port,
			this.target.host,
			this.target.port
		);
	
		// The actual SSH tunnel
		string [] command = [
			"ssh",
				"-L", tunnel,
				"-NnTxa",
				"-o", "ServerAliveInterval=300",
				this.hop
		];

		// Unblock all signals since the signal mask stays valid even in an exec
		signalsUnblock(SIGNALS);

		// Exec the command
		execvp(command[0], command);

		// Exec is not supposed to fail
		throw new ErrnoException("Exec failed");
	}

	
	/**
	 * Generic method used to manipulate an iptable rule. Action should either be
	 * "-A" for creating the rule or "-D" for deleting the rule.
	 */
	private void doIpTableRule (string action) {
		string command = format(
			"sudo iptables -v -t nat %s OUTPUT -p tcp --dport %d -d %s -j REDIRECT --to-ports %d",
			action,
			this.target.port,
			this.target.host,
			this.local.port
		);
		system(command);
	}
	
	string toString() {
		return format(
			"SSH tunnel %s:%s via %d", 
			this.target.host,
			this.target.port,
			this.local.port
		);
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
 * If the host can't be found the "null' will be returned.
 */
private NetworkAddress getNetworkAddress (string host) {
	
	string [] files = [
		expandTilde("~/.ssh/config"),
		"/etc/ssh/ssh_config",
	];

	foreach (string file; files) {
		NetworkAddress address = getNetworkAddress(host, file);
		if (address !is null) {
			return address;
		}
	}

	return null;
}
