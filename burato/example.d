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
 * APIs or code snippets.
 */

private import std.stdio;

private import burato.ssh.manager;
private import burato.save.tunnels;
private import glib.Util;
private import glib.Str;
private import gtkc.glib: g_malloc, g_free;
private import std.stdarg;
private import glib.FileUtils;

private import std.c.linux.linux:
	SIGINT,
	SIGTERM,
	SIGQUIT
;


/**
 * Main entry point of the program.
 */
int main (string [] args) {
	writefln("Test");

	const int [] signals = [
		SIGINT,
		SIGTERM,
		SIGQUIT,
	];
	SshManager manager = new SshManager(signals);
	writefln("Executing '%s'", Util.getPrgname());

	string saveFile = Util.buildFilename(
		Util.getUserConfigDir(),
		"ssh-tunnels",
		"save.xml"
	);
	writefln("saveFile is %s", saveFile);

	if (! FileUtils.fileTest(saveFile, GFileTest.EXISTS | GFileTest.IS_REGULAR)) {
		writefln("File doesn't exist");
		return 1;
	}
	
	loadSshTunnels(manager, saveFile);
	manager.waitForTunnelsToDie();

	writefln("Ok");
	return 0;
}
