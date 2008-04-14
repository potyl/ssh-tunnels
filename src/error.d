/**
 * Simple wrapper over errno and an Exception that supports formatted strings.
 */
module burato.error;


private import std.stdarg;
private import std.string:
	format,
	toString
;


private import std.c.process: _exit;
private import std.c.string: strerror;
private import std.c.stdlib: getErrno;


/**
 * This Exception class enables the message string to be formatted with the same
 * formats as "doFormat".
 */
class FormattedException : Exception {
	this(...) {
		super(my_format(_arguments, _argptr));
	}
}


/**
 * This Exception class enables the message string to be formatted with the same
 * formats as "doFormat" but it also appends the "errno" message at the end.
 */
class ErrnoException : Exception {
	this(...) {
		super(
			format(
				"%s: %s",
				my_format(_arguments, _argptr),
				getError()
			)
		);
	}
}


/**
 * Returns the last errno message encountered.
 */
private string getError () {
	int errno = getErrno();
	char *cString = strerror(errno);
	string message = toString(cString).dup;
	return message;
}


/**
 * Custom wrapper that calls "doFormat", this wrapper is needed in order to
 * forward the call of the "FormattedException" constructor to "doFormat".
 */
private string my_format(TypeInfo[] arguments, va_list argptr) {

	string text;

	void putc(dchar c) {
		std.utf.encode(text, c);
	}

	std.format.doFormat(&putc, arguments, argptr);
	return text;
}
