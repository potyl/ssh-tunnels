/*
 * network.d
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

private import burato.error: FormattedException;


/**
 * Representation of an Address (host, port).
 *
 * This class is almost identical to an InternetAddress, the main difference is
 * that here the host is not resolved into an IP address.
 */
public class NetworkAddress {

	const string host;
	const ushort port;

	this(string host, ushort port) {
		this.host = host;
		this.port = port;
	}
}


/**
 * Finds the local address to used for the connection to the given host.
 *
 * Throws SocketException if an error occurs with the socket or 
 * FormattedException if the local address is not an InternetAddress.
 */
public InternetAddress getLocalAddress (NetworkAddress address) {

	// Prepare the socket
	Socket socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);

	// Connect to the remote end
	socket.connect(new InternetAddress(address.host, address.port));
	
	// Get the local address and and quit
	Address remote = socket.localAddress();
	socket.close();
	
	// Make sure that we have an Internet address
	if (remote.addressFamily != AddressFamily.INET) {
		throw new FormattedException(
			"Socket to %s:%d is of wrong address family (%s)", 
			address.host, address.port, remote
		);
	}
	InternetAddress inetAddress = cast(InternetAddress) remote;
	
	return inetAddress;
}
