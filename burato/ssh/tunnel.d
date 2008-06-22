/*
 * tunnel.d - wraps an iptables rule for a single port redirection.
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

module burato.ssh.tunnel;

/**
 * This module provides the class Tunnel which is used to wrap a single SSH port
 * redirection that's paried with a custom iptables rule.
 *
 * This class is used to control the iptables rule that correspond to a single
 * SSH tunnel. The tunnel is controlled by an SSH process that's wrapped around
 * an instance of Connection.
 *
 * A tunnel is a point to point connection, thus it requires a local address
 * (host and port) and a target address (host and port).
 */

private import std.stdio;
private import std.c.linux.linux: pid_t;
private import std.process: system;
 
private import burato.network;


package class SshTunnel {
	
	const NetworkAddress local;
	const NetworkAddress target;

	
	/**
	 * Creates a new Tunnel instance. This tunnel is not yet connected, this has
	 * to be performed through the method "connect".
	 */
	package this(NetworkAddress local, NetworkAddress target) {
		this.local = local;
		this.target = target;
	}
	
	
	/**
	 * Connects the tunnel by creating an SSH tunnel and creating the
	 * corresponding iptables rule.
	 */
	package void connect () {
		// Create the iptable rule
		writefln("Creating an iptables rules to %s:%d via port %d",
			this.target.host,
			this.target.port,
			this.local.port
		);
		this.doIpTableRule("-A");
	}

	
	/**
	 * Disconnects the tunnel by closing the SSH tunnel and removing the
	 * corresponding iptables rule.
	 */
	package void disconnect () {
		// Delete the iptable rule
		this.doIpTableRule("-D");
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
	

	public string toString() {
		return format(
			"SSH tunnel %s:%s via %d", 
			this.target.host,
			this.target.port,
			this.local.port
		);
	}
}
