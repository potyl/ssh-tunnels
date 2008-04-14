module burato.signal;

private import std.c.linux.linux: sigset_t;

typedef void (*sighandler_t) (int);


private enum SigProcMaskHow : int {
	SIG_BLOCK   = 0, // Block signals.
	SIG_UNBLOCK = 1, // Unblock signals.
	SIG_SETMASK = 2, // Set the set of blocked signals.
}


// Fake signal functions copied from /usr/include/bits/signum.h
const sighandler_t SIG_ERR  = cast(sighandler_t) -1;
const sighandler_t SIG_DFL  = cast(sighandler_t)  0;
const sighandler_t SIG_IGN  = cast(sighandler_t)  1;
const sighandler_t SIG_HOLD = cast(sighandler_t)  2;


extern (C) {
	sighandler_t signal (int signal, sighandler_t handler);

	private int sigemptyset (sigset_t *set);
	private int sigaddset (sigset_t *set, int signum);

	private int sigprocmask (SigProcMaskHow how, sigset_t *set, sigset_t *oldset);
}


/**
 * Creates a sigset_t based on the given signals.
 */
private sigset_t* makeSigset (int [] signals) {
	
	sigset_t *sigset = new sigset_t;
	sigemptyset(sigset);
	
	foreach (int sig; signals) {
		sigaddset(sigset, sig);
	}
	
	return sigset;
}


/**
 * Unblocks the given signals. This function is ususally called after "signalsBlock".
 *
 * Consider using "runUninterrupted" instead.
 */
void signalsUnblock (int [] signals) {
	sigset_t *sigset = makeSigset(signals);
	signalsUnblock(sigset);
}

private void signalsUnblock (sigset_t *sigset) {
	sigprocmask(SigProcMaskHow.SIG_UNBLOCK, sigset, null);
}


/**
 * Blocks the given signals. To unblock the signals call "signalsUnblock".
 *
 * Consider using "runUninterrupted" instead.
 */
void signalsBlock (int [] signals) {
	sigset_t *sigset = makeSigset(signals);
	signalsBlock(sigset);
}

private void signalsBlock (sigset_t *sigset) {
	sigprocmask(SigProcMaskHow.SIG_BLOCK, sigset, null);
}


/**
 * Runs a delegate while the given signals are blocked. After the delegate has
 * resumed the signals are unblocked.
 */
void runUninterrupted (void delegate() task, int [] signals) {

	// Block the signals
	sigset_t *sigset = makeSigset(signals);
	signalsBlock(sigset);
	
	try {
		// Run the task
		task();
	}
	finally {
		// Unblock the signals
		signalsUnblock(sigset);
	}
}
