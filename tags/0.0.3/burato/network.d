/*
 * network.d - Network utilities.
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

module burato.network;

/**
 * This module provides utility functions and classes for dealing with 
 * networking.
 */

private import std.socket;
private import std.string: format;

private import burato.error: FormattedException;


/**
 * Representation of an Address (host, port).
 *
 * This class is almost identical to an InternetAddress, the main difference is
 * that here the host is not necessarily resolved into an IP address.
 */
public class NetworkAddress {

	const string host;
	const ushort port;

	public this(string host, ushort port) {
		this.host = host;
		this.port = port;
	}
	
	public string toString() {
		return format(
			"%s(host=%s, port=%d)", 
			super.toString(), 
			this.host, 
			this.port
		);
	}
}


/**
 * Finds a local address to use for the connection to the given host. This 
 * function tries to find a free port that can be used for connection to the
 * given remote address.
 *
 * This function assumes that if a TCP/IP connection is made with a 'reusable'
 * random port, that the port will NOT be reused by the OS for a short lapse of
 * time unless if requested explicitly. Thus if another process requests a
 * socket without specifiying a port that the new port returned will not be the
 * one that was given to this function.
 *
 * Throws SocketException if an error occurs with the socket or 
 * FormattedException if the local address is not an InternetAddress.
 */
public NetworkAddress getLocalAddressForRemoteConnection (NetworkAddress remoteAddress) {

	// Prepare the socket
	Socket socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

	// Connect to the remote end
	socket.connect(new InternetAddress(remoteAddress.host, remoteAddress.port));
	
	// Get the local address and and quit
	Address local = socket.localAddress();
	socket.close();
	
	// Make sure that we have an Internet address
	if (local.addressFamily != AddressFamily.INET) {
		throw new FormattedException(
			"Socket to %s:%d is of wrong address family (%s)", 
			remoteAddress.host, remoteAddress.port, local
		);
	}
	InternetAddress inetAddress = cast(InternetAddress) local;
	
	NetworkAddress localAddress = new NetworkAddress(
		inetAddress.toAddrString(), 
		inetAddress.port
	);
	
	return localAddress;
}
