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

//private import std.c.stdlib;

/**
 * Main entry point of the program.
 */
int main (string [] args) {
	writefln("Test");
	
	if (args.length < 1) {
		writefln("Usage: xml");
		return 1;
	}

	string text = cast(char[]) std.file.read(args[1]);


	//string text = "<save><connection target='festival'><tunnel target='irc.perl.org' port='6667'/></connection></save>";

	XMLParser parser = new MyXMLParser();
	parser.parse(text);

	writefln("Ok");
	return 0;
}


/**
 * Custom XML parser.
 */
class MyXMLParser : XMLParser {
	
	void onStartElement (string name, string [string] attributes) {
		writefln("<%s>", name);
		writefln("\tAttributes: %s", attributes);
	}

	void onEndElement (string name) {
		writefln("</%s>", name);
	}

	void onText (string text) {
		writefln("\tText: %s", text);
	}

	void onPassthrough (string text) {
		writefln("\tPassthrough: %s", text);
	}
}


/**
 * Basic XML Parser (a pseudo SAX parser) that' based on SimpleXML. This parser
 * is object oriented and relies on methods instead of functions.
 *
 * The parser can be overloaded by defining the following methods:
 *
 *  onError - called when an error is encoutered
 *  onStartElement - called when an element is started
 *  onEndElement - called when an element is ended
 *  onText - called when text is being processed
 *  onPassthrough - called when non text data (PI, comments) is bein processed
 *  
 * The method parse(xml) can be used to parse an XML string.
 *
 * This class gives a more object oriented interface to SimpleXML, futhermore it
 * also makes the methods look more 'D' as it uses 'D' types for the method
 * arguments.
 *
 * As a drawback the SimpleXML instance as all callbacks registered, even if the
 * derived class doesn't overload them all.
 */
class XMLParser {

	private SimpleXML simpleXML;
	
	
	/**
	 * Creates a new instance.
	 *
	 * Parsing is done through the method parse(xml).
	 */
	this () {
		static GMarkupParser parser = {
			error: &callbackError,
			startElement: &callbackStartElement,
			endElement: &callbackEndElement,
			text: &callbackText,
			passthrough: &callbackPassthrough,
		};

		this.simpleXML = new SimpleXML(
			cast(GMarkupParser *) &parser, 
			cast(GMarkupParseFlags) 0, 
			cast(gpointer) this, 
			cast(GDestroyNotify) null
		);
	}

	
	/**
	 *
	 */
	private static void callbackError (GMarkupParseContext *context, GError *error, gpointer userData) {
		XMLParser that = cast(XMLParser) userData;
		that.onError();
	}

	
	private static void callbackStartElement (
		GMarkupParseContext *context,
		gchar *elementName,
		gchar **attributeNames,
		gchar **attributeValues,
		gpointer userData,
		GError **error
	) {

		// Transform the attributes into an hash
		string [string] attributes;
		while (true) {
			string name = Str.toString(*attributeNames++);
			string value = Str.toString(*attributeValues++);
			if (name is null) {break;}
	
			attributes[name] = value;
		}

		string element = Str.toString(elementName);

		// Invoke the callback
		XMLParser that = cast(XMLParser) userData;
		that.onStartElement(element, attributes);
	}


	private static void callbackEndElement (
		GMarkupParseContext *context,
		gchar *elementName,
		gpointer userData,
		GError **error
	) {
		string name = Str.toString(elementName);

		// Invoke the callback
		XMLParser that = cast(XMLParser) userData;
		that.onEndElement(name);
	}


	private static void callbackText (
		GMarkupParseContext *context,
		gchar *text,
		gsize textLen,
		gpointer userData,
		GError **error
	) {
		
		string buffer = toString(text, textLen);
		
		// Invoke the callback
		XMLParser that = cast(XMLParser) userData;
		that.onText(buffer);
	}


	private static void callbackPassthrough (
		GMarkupParseContext *context,
		gchar *passthroughText,
		gsize textLen,
		gpointer userData,
		GError **error
	)
	{
		string buffer = toString	(passthroughText, textLen);
		
		// Invoke the callback
		XMLParser that = cast(XMLParser) userData;
		that.onPassthrough(buffer);
	}


	private static string toString (gchar *text, gsize textLen) {
		
		// Transform the C string into a D string
		string buffer;
		buffer.length = textLen;
		for (gsize i = 0; i < textLen; ++i) {
			buffer[i] = text[i];
		}
		
		return buffer;
	}


	void onError () {}
	void onStartElement (string name, string [string] attributes) {}
	void onEndElement (string name) {}
	void onText (string text) {}
	void onPassthrough (string text) {}


	/**
	 * Parses an XML document loaded into a string.
	 */
	void parse (string xml) {
		GError *error;
		this.simpleXML.parse(xml , xml.length, &error);
	}
}
