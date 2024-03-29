/*
 * main/gtk/gtk.d
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

module burato.main.gtk.gtk;

/**
 * This module provides a program with a graphical frontend that can be used to
 * start new SSH tunnels that are each backed by a corresponding iptable rule.
 *
 * This program is expected to be with a graphical desktop and lies in the
 * system tray once the tray icon is activated the main window will be visible.
 *
 * To stop the program simply right click on the tray icon and select "quit".
 * This will cause the program to gracefully close all tunnels and to remove the
 * corresponding iptable rules.
 *
 * If an individual tunnel dies or is killed the program should detect it an
 * remove the corresponding iptable rule.
 *
 * NOTE: If the program is killed with the signal "KILL" (9) then no clean will
 *       be made. This means that the iptable rules might still be available.
 */

private import std.stdio;
private import std.string;
private import std.path:
	getDirName,
	join,
	pathsep
;
private import std.file: 
	getcwd, 
	chdir,
	exists
;

private import std.process: waitpid ,pid_t;

private import std.c.linux.linux:
	SIGINT,
	SIGTERM,
	SIGQUIT,
	SIGCHLD
;

private import std.c.stdlib: getenv;


private import gtk.Main;
private import gtk.Window;
private import gtk.StatusIcon;
private import gtk.Widget;
private import gtk.Button;
private import gtk.Button;
private import gtk.Entry;
private import gtk.SpinButton;
private import gtk.Menu;
private import gtk.MenuItem;
private import gtk.AboutDialog;
private import gtk.Dialog;

private import gtk.TreeView;
private import gtk.TreeViewColumn;
private import gtk.CellRendererText;
private import gtk.TreeIter;

private import gdk.Keymap;
private import gdk.Event;
private import gdk.Rectangle;
private import gobject.Value;

private import glade.Glade;

private import glib.Util;
private import glib.FileUtils;

private import burato.signal: 
	signal,
	runUninterrupted,
	SIG_IGN
;
private import burato.ssh.manager;
private import burato.ssh.connection;
private import burato.ssh.tunnel;
private import burato.network;
private import burato.main.gtk.store;
private import burato.save.tunnels;


/**
 * Constant used by waitpid in order to return right away.
 *
 * Stolen from /usr/include/bits/waitflags.h
 */
private const int WNOHANG = 1;


/**
 * This is the application's main instance that's being executed. This is needed
 * because the signal handlers take functions and not delegates.
 */
private Application APPLICATION;


/**
 * The signals that are blocked during critical sections. For now only the
 * creation and the removal of a tunnel is critical enough.
 */
private const int [] SIGNALS = [
	SIGINT,
	SIGTERM,
	SIGQUIT,
];


/**
 * Path where the resources are expected to be found.
 *
 * NOTE: This variable will be set at runtime.
 */
private string RESOURCE_PATH = ".";


class Application {
	
	private const Glade glade;
	private const Window window;
	private const StatusIcon statusIcon;
	
	private const Button createTunnelButton;
	private const Entry hopField;
	private const SpinButton portField;
	private const Entry targetField;
	private const AboutDialog aboutDialog;
	private const TreeView treeView;
	
	private const Menu menu;
	
	private const TunnelsListStore store;
	
	
	/**
	 * Track the visibility of the main window.
	 */
	private bool mainWindowVisible = false;
	
	/**
	 * Track the position of the main window.
	 */
	private int mainWindowX = 0;
	private int mainWindowY = 0;


	/**
	 * Constructor. It requires the path to a glade file.
	 */
	this (string file) {

		this.glade = new Glade(file);
		if (this.glade is null) {
			throw new Exception("Can't parse file: " ~ file);
		}
		
		this.window = this.getGladeWidget!(Window)("window");
		this.createTunnelButton = this.getGladeWidget!(Button)("create");
		this.hopField = this.getGladeWidget!(Entry)("hop");
		this.portField = this.getGladeWidget!(SpinButton)("port");
		this.targetField = this.getGladeWidget!(Entry)("target");
		this.menu = this.getGladeWidget!(Menu)("menu");
		this.treeView = this.getGladeWidget!(TreeView)("treeview");
		
		this.aboutDialog = this.getGladeWidget!(AboutDialog)("dialog-about");
		
		this.statusIcon = new StatusIcon(getResourcePath("ssh-tunnels.png"), true);
		
		this.store = new TunnelsListStore(SIGNALS);
		
		this.finalizeWidgets();
	}


	/**
	 * Finalizes the main widgets by registering the callbacks and completing all
	 * widgets left unfinalized by Glade.
	 */
	private void finalizeWidgets () {
		
		// Toggle the visibility of the main window
		this.statusIcon.addOnActivate(&onStatusIconClicked);
		this.statusIcon.addOnPopupMenu(&onStatusIconShowPopupMenu);
		
		// Track the visibility of the main window
		this.window.addOnDelete(&onWindowDelete);
		this.window.addOnShow(&onWindowShow);
		this.window.addOnHide(&onWindowHide);
		
		this.createTunnelButton.addOnClicked(&onCreateTunnelClicked);


		// The about dialog (make sure that it doesn't die)
		this.aboutDialog.addOnResponse(&onDialogResponse);
		this.aboutDialog.addOnClose(&onDialogClose);
		this.aboutDialog.addOnDelete(&onWindowDelete);


		// Application popup menu
		this.menuAddOnActivate("menu-about", &onMenuItemShowAboutDialog);
		this.menuAddOnActivate("menu-quit", &onMenuItemQuit);

		
		// Complete the Tunnel's TreeView widget and it's store
		this.setupTunnelsView();
	}

	
	private gboolean onDeleteTunnel (GdkEventKey *event, Widget widget) {
		
		if (Keymap.gdkKeyvalFromName("Delete") != event.keyval) {
			return false;
		}
		
		TreeIter iter = this.treeView.getSelectedIter();
		if (iter !is null) {
			this.store.closeSshConnection(iter);
		}
		return true;
	}	


	/**
	 * Callback called the the about dialog should be displayed.
	 */
	private void onMenuItemShowAboutDialog (MenuItem menuItem) {
		this.aboutDialog.present();
	}
	

	/**
	 * Callback called the quit menu has been selected. This means that the
	 * application must exit.
	 */
	private void onMenuItemQuit (MenuItem menuItem) {
		this.quit();
	}
	
	
	/**
	 * Registers the given "OnActivate" callback with the given menu.
	 */
	private void menuAddOnActivate (string name, void delegate(MenuItem) callback) {
		MenuItem menuItem = this.getGladeWidget!(MenuItem)(name);
		menuItem.addOnActivate(callback);
	}


	/**
	 * Callback called when the about dialog is going to be closed. Here we just
	 * want hide the dialog since Glade will not recreate it.
	 */
	private void onDialogResponse (int response, Dialog dialog) {
		if (response == GtkResponseType.GTK_RESPONSE_CANCEL) {
			// FIXME hideOnDelete is a callback not a function that should be called
			dialog.hideOnDelete();
		}
	}


	/**
	 * Callback called when the about dialog is going to be closed. Here we just
	 * want hide the dialog since Glade will not recreate it.
	 */
	private void onDialogClose (Dialog dialog) {
			// FIXME hideOnDelete is a callback not a function that should be called
		dialog.hideOnDelete();
	}


	/**
	 * Callback called when the status icon is clicked. Usually here we show the
	 * main window.
	 */
	private void onStatusIconClicked (StatusIcon widget) {
		if (this.mainWindowVisible) {
			// FIXME hideOnDelete is a callback not a function that should be called
			this.window.hideOnDelete();
		}
		else {
			this.window.present();
		}
	}
	

	/**
	 * Callback called when the status icon has to show a popup menu.
	 */
	private void onStatusIconShowPopupMenu (guint button, guint time, StatusIcon widget) {
		this.menu.popup(null, null, &menuPositionFunc, cast(void *) widget, button, time);
	}
	
	
	/**
	 * Calculates the position of the menu popup in order to be next to the status
	 * icon instead of being over it. The parameter 'data' is expected to be an
	 * instance of StatusIcon.
	 */
	private static extern(C) void menuPositionFunc (GtkMenu *gtkMenu, gint *x, gint *y, gboolean *push_in, void *data) {

		StatusIcon icon = cast(StatusIcon) data;

		// Get the position of the status icon
		GdkRectangle gdkArea;
		Rectangle area = new Rectangle(&gdkArea);
		gboolean filled = icon.getGeometry(null, area, null);
		if (!filled) {
			return;
		}
		
		// Place the popup where the status icon is 
		*x = gdkArea.x;
		*y = gdkArea.y;

		// Check in which part of the screen is the y coordinate (above or below)
		auto screen = icon.getScreen();
		if (*y > (screen.getHeight()/2)) {
			// below part
			GtkRequisition requisition;
			Menu menu = new Menu(gtkMenu);
			menu.sizeRequest(&requisition);
			*y -= requisition.height + 1;
		}
		else {
			// above part
			*y += gdkArea.height + 1;
		}
	}

	
	/**
	 * Callback called when the close button on the main window is clicked. Here
	 * we want to hide the window.
	 */
	private gboolean onWindowDelete (Event event, Widget widget) {
		return widget.hideOnDelete();
	}

	
	/**
	 * Callback called when the main window is hidden. This callback is used to
	 * track the coordinates and the visibility of the window.
	 *
	 * In theory the visibility shouldn't need to be tracked but because gtkD
	 * doesn't support yet GTK_WIDGET_VISIBLE(), this is performed here.
	 */
	private void onWindowHide (Widget widget) {
		if (widget !is this.window) {
			return;
		}

		// Track the visibility and the position
		this.mainWindowVisible = false;
		widget.getWindow().getOrigin(&this.mainWindowX, &this.mainWindowY);
	}


	/**
	 * Callback called when the main window is shown. This callback is used to
	 * track the coordinates and the visibility of the window.
	 *
	 * In theory the visibility shouldn't need to be tracked but because gtkD
	 * doesn't support yet GTK_WIDGET_VISIBLE(), this is performed here.
	 */
	private void onWindowShow (Widget widget) {
		if (widget !is this.window) {
			return;
		}

		// Track the visibility and the position
		this.window.move(this.mainWindowX, this.mainWindowY);
		this.mainWindowVisible = true;
	}

	
	/**
	 * Callback called when a new tunnel should be created.
	 */
	private void onCreateTunnelClicked (Button button) {

		string hop = this.getValue(this.hopField);
		uint port = cast(uint) this.portField.getValue();
		string target = this.getValue(this.targetField);
		
		if (hop is null || target is null) {
			writefln("Parameters empty can't create a tunnel");
			return;
		}
		
		
		NetworkAddress [] targetAddresses = [
			new NetworkAddress(target, port)
		];
		this.store.add(hop, targetAddresses);
	}
	

	// Signal handler used to monitor the tunnel that dies
// FIXME enabling this creates some problems with the call to system in tunnel.doIpTableRule
// replace by an idle event that will perform waitpid on the pids of the tunnels started
//	signal(SIGCHLD, &monitorTunnelsSighandler);
//	private gboolean onIdleWaitpid (void* data) {
//	private bool onIdleWaitpid () {
//
//		// Get as much PIDs as we can
//		while (true) {
//			
//			// Get the next PID available
//			int status;
//			pid_t pid = waitpid(-1, &status, WNOHANG);
//			if (pid < 1) {
//				// No more PIDs for the moment
//				writefln("no process to wait for");
//				return true;
//			}
//
//			// Close the tunnel
//			writefln("==> asking to close SSH tunnel for pid %d", pid);
//			this.store.closeSshConnection(pid);
//		}
//
//		writefln("running an idle event");
//		return true;
//	}


	
	/**
	 * Gets the value of the given GtkEntry. The value will be striped of all
	 * leading and trailing white spaces. If the value is empty then null will be
	 * returned instead.
	 */
	private string getValue (Entry entry) {

		string value = entry.getText();

		if (value is null) {
			return null;
		}
		value = strip(value);
		
		return cmp(value, "") == 0 ? null : strip(value);
	}

	
	/**
	 * Returns the Glade widget that has the given name. If the widget can't be
	 * found the method throws an Exception.
	 *
	 * The widget is already casted to the proper type.
	 */
	private T getGladeWidget (T) (string name) {
		T widget = cast(T) this.glade.getWidget(name);
		if (widget is null) {
			throw new Exception("No such glade widget " ~ name);
		}
		return widget;
	}


	/**
	 * Initializes the view displaying the Tunnels opened so far.
	 *
	 */
	private void setupTunnelsView () {
		
		// Set the tree view
		this.treeView.setModel(this.store);
		this.treeView.setHeadersClickable(true);
		this.treeView.setRulesHint(true);
		
		string [] titles = [
			"Hop",
			"Port",
			"Tatget",
		];
		
		// Create the columns
		foreach (size_t pos, string title; titles) {
			
			TreeViewColumn column = new TreeViewColumn(
				title, 
				new CellRendererText(), 
				"text", 
				pos
			);
			column.setReorderable(true);
			column.setSortColumnId(pos);
			column.setSortIndicator(true);
			column.setResizable(true);

			treeView.appendColumn(column);
		}
		
		treeView.addOnKeyRelease(&onDeleteTunnel);
	}
	
	
	/**
	 * Quits the application. Before quiting all tunnels will be closed.
	 */
	void quit () {
		
		// NOTE Make sure that we deregister our SIGCHLD reaper. This has to be done
		//      for two reasons: 
		//      1- We are going to kill all tunnels so no need to catch the signals
		//      2- The tunnels are closed using system and the signal handler seems
		//         to interfere with it, the program hangs there.
		//
		// See http://www.schwer.us/journal/2008/02/06/perl-sigchld-ignore-system-and-you/
		signal(SIGCHLD, SIG_IGN);
		
		writefln("Calling quit()");
		
		this.store.closeAll();
		
		writefln("Calling Main.quit()");
		Main.quit();
	}
	
	
	/**
	 * Loads a save file and creates the SSH connections registered there.
	 */
	void loadSaveFile(string saveFile) {
		writefln("Loading save file %s", saveFile);
		loadSshTunnels(this.store.manager, saveFile);
	}
	
}


/**
 * Main entry point of the program.
 */
int main (string [] args) {
	Main.init(args);
	
	// Resolve the application's path
	resolveResourcePath(args[0]);

	// Create the application
	string gladeFile = getResourcePath("ssh-tunnels.glade");
	APPLICATION = new Application(gladeFile);


	// Load the previous configuration file
	string saveFile = Util.buildFilename(
		Util.getUserConfigDir(),
		"ssh-tunnels",
		"save.xml"
	);
	writefln("saveFile is %s", saveFile);

	if (FileUtils.fileTest(saveFile, GFileTest.EXISTS | GFileTest.IS_REGULAR)) {
		APPLICATION.loadSaveFile(saveFile);
	}



	// Register our own signal handler in order to catch all CTRL-C
	foreach (int sig; SIGNALS) {
		signal(sig, &quitSighandler);
	}
	

	// Go into the main loop
	Main.run();
	
	writefln("GTK main loop is now over");
	
	return 0;
}


/**
 * Custom signal handler that's called when a tunnel dies.
 */
void monitorTunnelsSighandler (int signal) {

	// Get as much PIDs as we can
	while (true) {
			
		// Get the next PID available
		int status;
		pid_t pid = waitpid(-1, &status, WNOHANG);
		if (pid < 1) {
			// No more PIDs
			break;
		}

		// Close the tunnel
		APPLICATION.store.closeSshConnection(pid);
	}
		
	return;
}


/**
 * Custom signal handler used to quit the application.
 */
private void quitSighandler (int sig) {
	writefln("Program caught a termination signal. Closing all tunnels.");

	APPLICATION.quit();
	
	std.c.stdlib._exit(0);
}


/**
 * Returns the path to the given resource.
 */
private string getResourcePath (string resource) {
	return join(RESOURCE_PATH, resource);
}


/**
 * Resolves the application's path by inspecting the the executable's path.
 */
private void resolveResourcePath (string executablePath) {
	
	// Remember the current folder
	string cwd = getcwd();
	
	// Chdir to the resource folder and get the current path
	string executableFolder = getDirName(executablePath);
	
	// If we have no folder is probably because the program was called directly
	// without a full or relative path and the PATH environment variable was used
	// to resolve the binary's path.
	if (cmp(executableFolder, "") == 0) {
		writefln("Parent folder not found");
		// Called without an absolute path andby using the PATH.
		string fullpath = whichExecutable(executablePath); 
		if (fullpath is null) {
			writefln("Can't find the fullpath to %s", executablePath);
		}
		else {
			writefln("Fullpath is '%s'", fullpath);
			executablePath = fullpath;
		}
	
		// Try to find the executable folder with the new path
		executableFolder = getDirName(executablePath);
	}

	string resourceFolderRelative = join(executableFolder, "../share/ssh-tunnels");
	chdir(resourceFolderRelative);
	
	RESOURCE_PATH = getcwd();
	
	// Chdir back to the current folder
	chdir(cwd);
}


/**
 * Find the fullpath of the executable that's launched when the command "name"
 * is invoked through the shell wihtout specifying a path (full or relative).
 * This function will search the PATH environmet variable for the given command. 
 * 
 * Returns the path to the executable or null if not found.
 */
private string whichExecutable (string name) {
	string pathEnv = toString(getenv("PATH"));
	
	// Walk the PATH for the most exact math
	foreach (string path; split(pathEnv, pathsep)) {
		string fullpath = join(path, name);
		if (exists(fullpath)) {
			return fullpath;
		}
	}
	
	return null;
}
