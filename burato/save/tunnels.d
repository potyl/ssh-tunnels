/*
 * save/tunnels.d - Manage the saved SSH tunnels between restarts.
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

module burato.save.tunnels;

/**
 * This module provides a simple way for loading/saving the SSH connections and
 * their corresponding tunnels.
 */

private import std.stdio;
private import std.string: atoi;
private import std.file;

private import burato.ssh.manager;
private import burato.ssh.connection;
private import burato.network;
private import burato.xml.parser;


/**
 * Creates the SSH connections and their corresponding tunnels as described in
 * the given configuration file.
 */
public void loadSshTunnels (SshManager manager, string file) {
	MyXMLParser parser = new MyXMLParser(manager);
	string text = cast(char[]) std.file.read(file);
	parser.parse(text);
}


/**
 * Custom XML parser used to load the save file that stores the SSH connections
 * and the tunnels. The file is expected to be in XML and to follow the format:
 *
 * <save>
 *
 *  <connection target="festival">
 *    <tunnel target="irc.perl.org" port="6667"/>
 *    <tunnel target="irc.freenode.net" port="6667"/>
 *  </connection>
 *
 *  <connection target="torrent">
 *    <tunnel target="localhost" port="8088"/>
 *  </connection>
 * </save>
 *
 */
private class MyXMLParser : XMLParser {

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
