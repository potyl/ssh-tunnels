/*
 * fork.d
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

module burato.fork;

/**
 * This module provides a simple way for forking processes and executing
 * arbitrary code in the new process. The code to be execute is provided as a
 * delegate or as a function.
 */

private import std.c.linux.linux: pid_t, fork;
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
