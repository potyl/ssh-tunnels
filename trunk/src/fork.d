/**
 * Simple wrapper over the system call "fork". This wrapper expects the child's
 * task to be a funciton or a delegate.
 */
module burato.fork;

private import std.c.linux.linux:
	pid_t,
	fork
;
private import std.c.process: _exit;

private import burato.error: ErrnoException;


/**
 * Forks a new process and exectues the given task.
 *
 * Throws Exception if the fork fails.
 */
pid_t forkTask (void delegate() task) {

	// Fork a new process
	pid_t pid = fork();
	if (pid == -1) {
		// Fork failed
		throw new ErrnoException("Failed to fork");
	}
	else if (pid > 0) {
		// Parent
		return pid;
	}

	//// 
	// Child's code
		
	try {
		// Execute the child's task
		task();
	}
	catch (Exception exception) {
		exception.print();
	}
	finally {
		// Make sure that the child doesn't live further
		_exit(0);
	}

	return pid;
}


/**
 * Forks a new process and exectues the given task.
 *
 * Throws Exception if the fork fails.
 */
pid_t forkTask (void function() task) {
	auto callback = delegate void() {
		task(); 
	};
	return forkTask(callback);
}
