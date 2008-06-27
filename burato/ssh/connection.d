/*
 * connection.d - wraps a SSH process (pid_t) with the corresponding tunnels
 * (iptables redirection rules).
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

module burato.ssh.connection;

/**
 * This module provides the class Connection which is used to wrap an single SSH
 * process that's using ports redirection with it's corresponding iptables
 * rules.
 *
 * The class Connection is used to create a transparent TCP/IP connection to a
 * remote host that's usually unreachable localy by using an SSH tunnel in
 * conjonction with an iptables rules. This has for effect of creating a direct
 * connection to the unreachable remote host. This is true even if firewall or
 * NATing rules forbid the access to the remote host. The tunneling is possible
 * as long as the SSH host has access to the target host and that the user
 * executing this program has the privileges to create an iptables rules.
 *
 * The OpenSSH client allows the creation of simulatenous SSH tunnels with a
 * single invocation. Thus a single SSH process can be used to redirect multiple
 * ports. This class takes advange of this fact and can handle mulitple port
 * redirections per SSH process.
 */

private import std.stdio;
private import std.c.unix.unix: kill;
private import std.c.linux.linux;
private import std.process: execvp;

private import burato.ssh.tunnel;
private import burato.network;
private import burato.fork;
private import burato.signal;

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
public class SshConnection {
	
	private pid_t pid_;
	private string hop_;

	private SshTunnel [] tunnels_;

	
	/**
	 * Creates a new instance. This Connection is not yet established, this has
	 * to be performed through the method "connect".
	 */
	package this(string hop, SshTunnel [] tunnels) {
		this.pid_ = 0;
		this.hop_ = hop;
		this.tunnels_ = tunnels;
	}
	
	
	/**
	 * Connects the tunnel by creating an SSH tunnel and creating the
	 * corresponding iptables rule.
	 */
	package pid_t connect () {
		// Create the SSH tunnel
		this.pid_ = forkTask(&this.createSshConnection);
		
		// Create the iptables rules
		foreach (SshTunnel tunnel; this.tunnels_) {
			tunnel.connect();
		}
		
		return this.pid_;
	}

	
	/**
	 * Disconnects the tunnel by closing the SSH tunnel and removing the
	 * corresponding iptables rule.
	 */
	package void disconnect () {

		// Kill the SSH tunnel
		kill(this.pid_, SIGTERM);
		
		// Delete the iptables rules
		foreach (SshTunnel tunnel; this.tunnels_) {
			tunnel.disconnect();
		}
	}


	/**
	 * Creates an SSH connection that will open the tunnels to the target.
	 *
	 * This method doesn't create the corresponding iptables rules.
	 */
	private void createSshConnection () {
		
		// Create the ssh args for the tunnels (-L port:host:port)
		string [] args = new string [this.tunnels_.length];
		
		foreach (int i, SshTunnel tunnel; this.tunnels_) {
			string arg = format("-L%d:%s:%d", 
				tunnel.local.port,
				tunnel.target.host,
				tunnel.target.port
			);
			args[i] = arg;
		}

	
		// Build the commad that will create the actual SSH tunnel
		string [] command = new string [5 + args.length];
		command[0] = "ssh";
		command[1] = "-NnTxa";
		command[2] = "-o";
		command[3] = "ServerAliveInterval=300";
		command[4 .. command.length - 1] = args;
		command[command.length - 1] = this.hop_;

		// Unblock all signals since the signal mask stays valid even in an exec
		signalsUnblock(SIGNALS);

		// Exec the command
		writefln("Creating SSH process: %s", command);
		execvp(command[0], command);

		// Exec is not supposed to fail
		throw new ErrnoException("Exec failed");
	}


	public pid_t pid () {
		return this.pid_;
	}
	public string hop () {
		return this.hop_;
	}
	public SshTunnel [] tunnels () {
		return this.tunnels_;
	}

	

	public string toString() {
		return format(
			"SSH connection to %s using PID %d with %d tunnels", 
			this.hop_,
			this.pid_,
			this.tunnels_.length
		);
	}
}
