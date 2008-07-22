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
private import std.string;
private import std.file;

private import glib.KeyFile;
private import glib.SimpleXML;
private import glib.Str;


private import burato.ssh.manager;
private import burato.ssh.connection;
private import burato.network;
private import burato.xml.parser;

private import std.c.process: exit;
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
	
	if (args.length < 2) {
		writefln("Usage: xml");
		return 1;
	}
	string text = cast(char[]) std.file.read(args[1]);


	const int [] signals = [
		SIGINT,
		SIGTERM,
		SIGQUIT,
	];
	SshManager manager = new SshManager(signals);


	XMLParser parser = new MyXMLParser(manager);
	parser.parse(text);

	manager.waitForTunnelsToDie();

	writefln("Ok");
	return 0;
}


/**
 * Custom XML parser.
 */
class MyXMLParser : XMLParser {

	SshManager manager;
	string hop = null;
	NetworkAddress [] addresses;
	
	this (SshManager manager) {
		this.manager = manager;
	}

	
	void onStartElement (string name, string [string] attributes) {
try {
		switch (name) {

			// Used to check if the attributes have a given key
			string *pointer;

			case "connection":
			{
				// Starting a new connection
				this.addresses = this.addresses.init;
				this.hop = null;

				pointer = ("target" in attributes);
				if (pointer is null) {return;}
				this.hop = *pointer;
			}
			break;
			

			case "tunnel":
			{
				// Adding a tunnel to the current connection
				pointer = ("target" in attributes);
				if (pointer is null) {return;}
				string host = *pointer;

				pointer = ("port" in attributes);
				if (pointer is null) {return;}
				ushort port = cast(ushort) atoi(*pointer);
				

				this.addresses.length = this.addresses.length + 1;
				this.addresses[length - 1] = new NetworkAddress(host, port);
			}
			break;
			
			
			default:
				// Other elements are not handled
			break;
		}

}
catch (Exception exception) {
	writefln("1 >> FAILED: %s", exception);
}

	}


	void onEndElement (string name) {
		
		if (name == "connection") {

			// Create a new SSh connection with the given tunnels
			if (this.hop is null) {return;}
			if (this.addresses.length < 1) {return;}

			try {
				this.manager.createSshConnection(this.hop, this.addresses);
			}
			catch (Exception exception) {
				writefln("2 >> FAILED: %s", exception);
			}
		}
	}
}
