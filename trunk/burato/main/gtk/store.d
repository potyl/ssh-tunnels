/*
 * main/gtk/store.d - Custom list store for the SSH tunnel
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

module burato.main.gtk.store;

/**
 * This module provides a program a custom list store that's used to display the
 * SSH tunnels that are currently open.
 */

private import std.stdio;

private import gobject.Value;

private import gtk.ListStore;
private import gtk.TreeIter;
private import gtk.TreePath;

private import burato.ssh.manager;
private import burato.ssh.connection;
private import burato.ssh.tunnel;
private import burato.network;

/**
 * Custom ListStore used to wrap the tunnels.
 *
 * Ideally this should be TreeStore as an SSH connection can have more than one
 * port.
 */
package class TunnelsListStore : ListStore {


	private static const GType [] COLUMNS = [
		GType.STRING,
		GType.INT,
		GType.STRING,
		GType.POINTER,
	];


	private class Item {
		SshConnection connection;
		TreeIter iter;
		
		this (SshConnection connection, TreeIter iter) {
			this.connection = connection;
			this.iter = iter;
		}
	}

	/**
	 * Make sure that we hold a reference to the tunnels. This is because we will
	 * pass them to the underlying gtk store which will hold a pointer to the
	 * tunnels. We need to keep a reference to the tunnles otherwise the garbage
	 * collector might collect the tunnels thinking there are no references to
	 * them.
	 */
	private Item [pid_t] items;

	package const SshManager manager;


	this (int [] signals) {
		super(COLUMNS);
		this.manager = new SshManager(signals);
		this.manager.addOnCloseCallback(&this.onSshConnectionClose);
		this.manager.addOnCreateCallback(&this.onSshConnectionCreate);
	}
	
	
	/**
	 * Creates an SSH connection and adds it to the store.
	 */
	void add (string hop, NetworkAddress [] targetAddresses) {
		this.manager.createSshConnection(hop, targetAddresses);
	}
	
	
	/**
	 * Closes the SSH connection that's backed by the given PID.
	 */
	void closeSshConnection (pid_t pid) {

		// Find the connection to discard in the hash
		Item *pointer = (pid in this.items);
		if (pointer is null) {
			return;
		}
		Item item = *pointer;
		this.discardSshConnection(item);
	}
	
	
	/**
	 * Closes the SSH connection designated by the given TreeIter from the store.
	 */
	void closeSshConnection (TreeIter iter) {
		
		// The path of the iter to remove
		TreePath path = this.getPath(iter);
		
		// Find the same path in the tree store
		foreach (Item item; items) {
			TreePath itemPath = this.getPath(item.iter);
			
			if (path.compare(itemPath) == 0) {
				// Remove the SSH connection corresponding to the given path
				this.discardSshConnection(item);
				return;
			}
		}
	}
	
	
	/**
	 * Callback called by the SshManager once a connection is closed. This usually
	 * happens when an SSH process dies (and the GUI wasn't involved). In this
	 * situation we simply remove the connection from the GUI.
	 */
	private void onSshConnectionClose (SshConnection connection) {
		// Simply call the method that closes the SSH connection. Of course there's
		// no need to close the connection since it's already closed but at least
		// the connection will be removed from the GUI.
		this.closeSshConnection(connection.pid);
	}
	
	
	/**
	 * Callback called by the SshManager once a connection is created. This is
	 * more of a confirmation that the actual SSH connection is made.
	 */
	private void onSshConnectionCreate (SshConnection connection) {
		Item item = new Item(connection, this.createIter());

		int pos = 0;
		this.setValue(item.iter, pos++, connection.hop);
		// FIXME For the moment the main GUI can create only one tunnel per SSH
		//       connection. This is because in the past the application could only
		//       handle one tunnel per connection. Now the framework allows the
		//       tunneling of multiple ports through one SSH connection.
		SshTunnel tunnel = connection.tunnels[0];

		this.setValue(item.iter, pos++, tunnel.target.port);
		this.setValue(item.iter, pos++, tunnel.target.host);

		{
			Value value = new Value();
			value.init(GType.POINTER);
			value.setPointer(cast(void*) tunnel);

			this.setValue(item.iter, pos++, value);
		}

		this.items[connection.pid] = item;
	}
	

	/**
	 * This method performs the removal of an SSH connection. At first it starts
	 * by removing the SSH connection from the SSH manager. This will close the
	 * SSH process if the process is still running and it will remove the iptables
	 * rules associated with the tunnels. Once the connection is removed from the
	 * SSH manager it will be also removed from the store, this will have for
	 * effect of removing the entry from the GUI.
	 */
	private void discardSshConnection (Item item) {
	
		pid_t pid = item.connection.pid;

		// Remove the SSH connection from the manager (kill pid, remove iptables)
		this.manager.removeSshConnection(pid);

		// Remove the entry from our items lookup
		this.items.remove(pid);

		// Remove the entry from the store (the GUI)
		this.remove(item.iter);
	}

	
	void closeAll () {
		//this.manager.closeSshConnections();
		
		foreach (Item item; this.items) {
			SshConnection connection = item.connection;
			writefln("quit >> Closing tunnel %s PID %d", connection, connection.pid);
			this.discardSshConnection(item);
//			connection.disconnect();
		}
	}	
}
