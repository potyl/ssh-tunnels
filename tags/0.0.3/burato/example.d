/*
 * example.d - small API tests
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

module burato.example;

/**
 * This module provides a simple executable that's used to expirement various
 * APIs.
 */

private import std.stdio;
private import std.string;


private import glib.Source;
private import glib.Timeout;
private import glib.MainLoop;


class Example {

	class Arg {
		Example object;
		gpointer arg;
		this (Example object, void *arg) {
			this.object = object;
			this.arg = arg;
		}
	};

	this () {
	
		gboolean function(gpointer data) fp  = function gboolean(gpointer data) { 
//			that.timeoutCallbackExampleD(data);
			writefln("function");
			return true;
		};
//		Timeout.addSeconds(1, cast(GSourceFunc) fp, null);
   
		
		string str = "Hello world".dup;
		Arg arg = new Arg(this, cast(gpointer)str);
		Timeout.addSeconds(1, cast(GSourceFunc) &callback, cast(gpointer)arg);

	
/*	
		auto dg = gboolean delegate (gpointer data) {
			writefln("delegate");
			return true;
		};
*/

//		Timeout.addSeconds(1, &timeoutCallbackExampleC, null);
//		Timeout.addSeconds(1, cast(GSourceFunc) &this.timeoutCallbackExampleD, null);

/*		extern (C) gboolean aaa (gpointer data) {
			writefln(">>>aaa");
			return true;
		}
		Timeout.addSeconds(1, &aaa, null);
*/
	}


	extern (C) private gboolean timeoutCallbackExampleC (gpointer data) {
		writefln("timeoutCallbackExample C");
		return true;
	}

	private gboolean timeoutCallbackExampleD (gpointer data) {
		auto str = cast(char *) data;
		writefln("timeoutCallbackExample D: %s", str);
		return true;
	}

	extern (C) static gboolean callback(gpointer data) {
		Arg arg = cast(Arg) data;
		return arg.object.timeoutCallbackExampleD(arg.arg);
	}
}


/**
 * Main entry point of the program.
 */
int main (string [] args) {
	
	writefln("Test");
	
	
//	Source timeout = Source.sourceNewSeconds(1);
//	Timeout.addSeconds(1, cast(GSourceFunc) &timeoutCallbackD, null);

//	Timeout.addSeconds(1, &timeoutCallbackC, null);
	
	
	Example example = new Example();
	
	// Start a main loop
	MainLoop loop = new MainLoop(null, true);
	loop.run();
	
	return 0;
}

extern (C) gboolean timeoutCallbackC (gpointer data) {
	writefln("Callback C");
	return true;
}

gboolean timeoutCallbackD (gpointer data) {
	writefln("Callback D");
	return true;
}
