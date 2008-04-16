/*
 * error.d
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

module burato.error;

/**
 * This module provides utilities for creating generic Exceptions that use
 * formatting strings ("%s") or that wrap the errno value in a more friendly 
 * way while providing support for formatting strings.
 */

private import std.stdarg;
private import std.string: format, toString;


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
