/*
 * ssh_config.d
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

module test.ssh_config;

/**
 * This module provides unit tests for the module ssh_config.
 */

import burato.ssh_config;
import std.stdio;

unittest {

	test("tock", "tock.nap.com.ar", 7777);
	test("maroochydore", "maroochydore.time.flexi4site.net", 8888);
	test("brisbane.time.flexi4site.net", "brisbane.time.flexi4site.net", 4234);
	test("yggdrasil", "yggdrasil.mrow.org", 3456);
	test("time", "time.aeraq.com", 9098);

	test("debian", "debian.ciencias.uchile.cl", 1033);
	test("ntp1v6", "ntp1v6.theremailer.net", 1243);

	test("winona", "winona.ziaspace.nl");

	test("ticktock", "ticktock.ewha.net");
	test("rtr.firmacem.ru", "rtr.firmacem.ru", 2332);
	test("ac-ntp2", "ac-ntp2.net.cmu.edu");

	test("rolex", "rolex.usg.edu");
	test("stratum2", "stratum2.ord2.publicntp.net");
	test("prometheus", "prometheus.acm.jhu.edu");

	test("horologe", "horologe.cerias.purdue.edu", 18097);
	test("time-ext", "time-ext.missouri.edu");
	test("ntppub", "ntppub.tamu.edu");

	test("andro", "andromeda.ziaspace.com");
	test("androm", "andromeda.ziaspace.com");
	test("andromeda", "andromeda.ziaspace.com");

	test("sun", "sundial.columbia.edu");

	test("sundial.", "sundial.cis.sac.accd.edu");
	test("sund", "sundial.cis.sac.accd.edu");
	test("sundial.cis", "sundial.cis.sac.accd.edu");

	test("ntp1.sibernet.com.tr", "ntp1.sibernet.com.tr");
	test("time.sibernet.com.tr", "time.sibernet.com.tr");
	test("ntp2.sibernet.com.tr", "ntp2.sibernet.com.tr");


	test("zg1", "zg1");
	test("ntp-public", "ntp-public");
	test("uber", "uber");

	// Not present in the file
	test("missing", "missing");
//
//	NetworkAddress address = getNetworkAddress("missing", "unittests/config");
//writefln("==ADDRESS = %s", address);
//	assert(address is null);
}


private void test(string host, string hostname, ushort port = 22) {

	writefln("\nTesting SSH config parsing for %s", host);
	NetworkAddress address = getNetworkAddress(host, "unittests/config");
	assert(address !is null);
	
	writefln("%s -> (%s, %d) expecting (%s, %d)", 
		host, 
		address.host, address.port, 
		hostname, port
	);
	bool passed = false;

	// Compare the hostnames
	passed = (address.host == hostname);
	if (! passed) {
		writefln("Host mismatch %s != %s for host %s", address.host, hostname, host);
	}
	assert(passed);

	// Compare the ports
	passed = (address.port == port);
	if (! passed) {
		writefln("Port mismatch %d != %d for host %s", address.port, port, host);
	}
	assert(passed);
}
