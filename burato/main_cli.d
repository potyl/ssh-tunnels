module burato.main_cli;

private import std.stdio;
private import std.string: atoi;
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
	if (args.length <= 3) {
		writefln("Usage: hop port host...");
		return 1;
	}
	string hop = args[1];
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
