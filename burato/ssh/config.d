/*
 * ssh/config.d - OpenSSH configuration parser.
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

module burato.ssh.config;

/**
 * This module provides utility functions for parsing an OpenSSH configuration
 * file as described in the man page ssh_config(5). The main purpose of this
 * module is to extract the hostname and port number that correspond to a given
 * SSH host.
 *
 * To summarize the ssh_config(5) man page: the OpenSSH configuration parameters
 * are defined within "Host" sections, this sections can use patterns to match a
 * given hostname. Futhermore multiple sections can match a given hostname in
 * this case when an extra section is parsed only new directictives are taken
 * into account. This way the first directive encoutered has precedence.
 *
 * The configuration of a host can spawn over multiple sections and through
 * multiple configuration files.
 */

private import std.stdio;
private import std.string;
private import std.path: fnmatch;

private import burato.network: NetworkAddress;


/**
 * The port normally used by all SSH servers.
 */
private const ushort SSH_DEFAULT_PORT = 22;


/**
 * Returns the NetworkAddress (hostname, port) to use when OpenSSH is presented
 * asked to connect ot the given host.
 *
 * This function tries to return the values of the configuration directives
 * "HostName" and "Port" that corresponds to the given host. The values are
 * returned in a NetworkAddress because the class will preserve the hostname
 * intact.
 *
 * Parameters:
 *   host:       the hostname where to connect to, expects the same format as
 *               OpenSSH, thus "root@mailserver" is a valid entry.
 *   directives: the OpenSSH default directives that override all other values.
 *   file:       the OpenSSH configuration file to parse.
 *
 * Returns:
 *   a NetworkAddress: hostname and port pair.
 * 
 */
public NetworkAddress getNetworkAddress(string host, string [string] directives, string [] files) {

	// Check if a user name was specified in the host name
	int pos = find(host, '@');
	if (pos > -1) {
		if (pos == host.length - 1) {
			// The string ends with an '@', there's nothing to do
			return new NetworkAddress(host, SSH_DEFAULT_PORT);
		}
		// Remove the user name from the host
		host = host[pos + 1 .. host.length];
	}
	
	// Make sure that the directives can store data
	if (directives is null) {
		string [string] hash;
		directives = hash;
	}
	else {
		string [string] copy;
		// Make sure that all keys are in lowercase
		foreach (string key, string value; directives) {
			string lower = tolower(key);
			directives[lower] = key;
		}
		directives = copy;
	}


	// Parse the configuration files
	foreach (string file; files) {
		// Scan the configuration file
		ConfigurationFile config = new ConfigurationFile(file);
		while (config.hasNextDirective()) {
		
			auto directive = config.nextDirective();
	
			// Look until we match the "Host" directive for the given host
			if (directive.matches("host", host)) {
				
				// Get the section's directives
				directives = config.loadSectionDirectives(directives); 
			}
		}
	}


	// Extract the hostname and the port from the directives
	string hostname = getDirectiveValue(directives, "hostname", host);
	string portString = getDirectiveValue(directives, "port", toString(SSH_DEFAULT_PORT));
	ushort port = atoi(portString);
			
	NetworkAddress address = new NetworkAddress(hostname, port);
	return address;
}


/**
 * Returns the value of the given directive from a directive section. If the
 * directive is not found then the default value is returned instead.
 *
 * Parameters:
 *   directives: the section's directives (an hash of key: string, value: string).
 *   name:       the name of the directive to lookup.
 *   fallback:   the default value to use if the directive can't be found.
 */
private string getDirectiveValue(string [string] directives, string name, string fallback) {

	// Check if the directive is available
	string *pointer = (name in directives);
	if (pointer is null) {
		// Return the default value as the directive is not available
		return fallback;
	}
	
	// Return the value of the directive
	return *pointer;
}


/**
 * Wrapper over a configuration file. This class provides a way to iterate over
 * the configuration parameters.
 *
 * This class reads the directives one by one with a buffer (for a single 
 * directive). When a "Host" section is parsed then the current directive (the
 * "Host" declaration) is put back into the buffer for a latter consumption.
 */
private class ConfigurationFile {
	
	/**
	 * The file handle of the configuration file being parsed.
	 */
	private FILE *handle;

	/**
	 * This buffer is used to store a directive that was parsed ahead and that
	 * will need to be reparsed latter. This happens usually at the end of a
	 * "Host" section.
	 */
	private ConfigurationDirective directive;

	
	this(string file) {
		this.handle = fopen(std.string.toStringz(file), "r");
		this.directive = null;
	}
	
	~this() {
		this.close();
	}
	
	private void close() {
		if (this.handle is null) {
			return;
		}

		fclose(this.handle);
		this.handle = null;
	}

	/**
	 * Returns true if a configuration directive can be pulled from the
	 * configuration file.
	 */
	private bool hasNextDirective() {
		
		if (this.directive) {
			return true;
		}
		
		while (this.handle && !feof(this.handle)) {

			// Get the next line of text
			string line = readln(this.handle);
			if (line is null) {
				this.close();
				return false;
			}

			// Check if the next line of text has a directive
			auto tmp = getConfigurationDirective(line);
			if (tmp) {
				this.directive = tmp;
				return true;
			}
		}
		
		return false;
	}


	/**
	 * Returns the next configuration directive available.
	 */
	private ConfigurationDirective nextDirective() {
		auto tmp = this.directive;
		this.directive = null;
		return tmp;
	}


	/**
	 * Loads the OpenSSH configuration directives defined in the current "Host"
	 * section.
	 *
	 * This function is meant to operate within a single "Host" section and will
	 * read all configuration directives until the end of file or the next "Host"
	 * section.
	 *
	 * This function returs the configuration directives in an hash table where the
	 * key is the configuration keyboard and the value the configuration value.
	 *
	 * Parameters:
	 *   directives: the directives loaded so far.
	 *
	 * Returns:
	 *   the directives loaded.
	 */
	string [string] loadSectionDirectives (string [string] directives) {
	
	
		// Now we're in the good "Host" section, let's find the "HostName" directive
		while (this.hasNextDirective()) {
			auto directive = this.nextDirective();
				
			// Make sure that we don't spawn over another host section
			if (directive.matches("host")) {
				// Make sure to remember this directive, in order to resume the loading
				// at the previous place
				this.directive = directive;
				break;
			}
			
			// Insert the directive only if it's the first time that it's seen
			string *pointer = (directive.keyword in directives);
			if (pointer is null) {
				directives[directive.keyword] = directive.value;
			}
		}


		return directives;
	}
}


/**
 * Representation of a SSH configuration directive. A directive is composed of a
 * keyword and a value.
 */
private class ConfigurationDirective {

	/**
	 * The keyword, the name of the directive.
	 */
	private const string keyword;
	
	/**
	 * The value of the directive.
	 */
	private const string value;


	/**
	 * The main constructor.
	 */
	this(string keyword, string value) {
		this.keyword = keyword;
		this.value = value;
	}


	/**
	 * Returns true if the given directive matches the given keyword and the given
	 * value. If a value is not provided or if it's "null" then the matche is only
	 * performed by comparing the keywords otherwise the value is used to match it
	 * against the directive value.
	 *
	 * NOTE: the value is compared using fnmatch, thus the characters "*", "?",
	 *       "[" and "]" have a special meaning.
	 *
	 */
	bool matches(string keyword, string value = null) {
		return 
				(cmp(this.keyword, keyword) == 0)
			&&
				( value is null || fnmatch(value, this.value) )
		;
	}


	string toString() {
		return format("%s(keyword=%s, value=%s)", super.toString(), this.keyword, this.value);
	}
}


/**
 * Extracts an OpenSSH configuration directive from the the given configuration
 * line. This parser is meant to parse the configuration directives described in
 * the man page ssh_config(5). If the line contains no directive or is a comment
 * then "null" will be returned.
 */
private ConfigurationDirective getConfigurationDirective (string text) {

	text = chomp(text);

	// Find the start of the configuration keyword name
	size_t start = 0;
	for (; start < text.length; ++start) {
		char c = text[start];
		if (! iswhite(c)) {
			break;
		}
	}
	
	// Check if there's a directive in the current line
	if (start == text.length || text[start] == '#') {
		return null;
	}
	
	
	// Find the end of the configuration keyword name
	size_t end = start;
	bool equal = false;
	for (; end < text.length; ++end) {
		char c = text[end];
		if (iswhite(c)) {
			break;
		}
		else if (c == '=') {
			equal = true;
			break;
		}
	}
	string keyword = text[start .. end];
	keyword = tolower(keyword);

	// If an equal sign is used then move the end position of one (after the '=')
	if (equal) {
		++end;
	}
	
	
	// Find the start of the value
	bool quoted = false;
	for (start = end; start < text.length; ++start) {
		char c = text[start];

		if (iswhite(c)) {
			continue;
		}
		else if (!equal && c == '=') {
			// Continue since we could be reading spaces or even find a quote
			equal = true;
			continue;
		}
		else if (!quoted && c == '"') {
			quoted = true;
			++start;
		}

		// Found the start of the value
		break;
	}

	// Find the end of the value
	end = quoted ? rfind(text, '"') : text.length;
	string value = text[start .. end];
	
	return new ConfigurationDirective(keyword, value);
}



//------------------------------------



/**
 * Returns the NetworkAddress (hostname, port) to use when OpenSSH is presented
 * asked to connect ot the given host.
 *
 * This function tries to return the values of the configuration directives
 * "HostName" and "Port" that corresponds to a matching "Host" section. The 
 * values are returned in a NetworkAddress because the class will preserve the
 * hostname intact.
 *
 * If the given host can't be matched with a "Host" directive then null will be
 * returned. This shouldn't be a problem as usually the file /etc/ssh/ssh_config
 * includes the default target "Host *" which will match everything. Thus make
 * sure that this function will be eventually called with the default OpenSSH
 * configuration file.
 *
 * Parameters:
 *   host: the hostname where to connect to, expects the same format as OpenSSH,
 *         thus "root@mailserver" is a valid entry.
 *   file: the OpenSSH configuration file to parse.
 *
 * Returns:
 *   NetworkAddress if a configuration section matches the host otherwise null.
 * @DEPRECATED
 */
public NetworkAddress getNetworkAddress(string host, string file) {
	string [string] directives;
	string [] files = [file];
	return getNetworkAddress(host, directives, files);
}
