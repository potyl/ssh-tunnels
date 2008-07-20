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

private import burato.network;
private import std.c.process: exit;

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

	XMLParser parser = new MyXMLParser();
	try {
		parser.parse(text);
	}
	catch (Error error) {
		writefln("Got error: %s", error);
	}
	catch (Exception exception) {
		writefln("Got exception: %s", exception);
	}

	writefln("Ok");
	return 0;
}


/**
 * Custom XML parser.
 */
class MyXMLParser : XMLParser {

	string hop = null;
	NetworkAddress [] addresses;
	
	private static string getAttributeValue (string [string] attributes, string name) {
		string *pointer;
		pointer = (name in attributes);
		if (pointer is null) {
			return null;
		}
		
		return *pointer;
	}

	
	void onStartElement (string name, string [string] attributes) {


writefln("Parsing %s", name);
	try {

		switch (name) {

			// Used to check if the attributes have a given key
			string *pointer;

			case "connection":
			{
				// Starting a new connection
//				hop = attributes["target"];
				pointer = ("target" in attributes);
				if (pointer is null) {
					// Incomplete tunnel entry
					return;
				}
				hop = *pointer;
				
//				hop = getAttributeValue(attributes, "target");
			}
			break;
			

			case "tunnel":
			{
				// Adding a tunnel to the current connection
				pointer = ("target" in attributes);
				if (pointer is null) {return;}
				string host = *pointer;

				pointer = ("port" in attributes);
				if (pointer is null) {
					// Incomplete tunnel entry
					return;
				}
				ushort port = cast(ushort) atoi(*pointer);
				

				addresses.length = addresses.length + 1;
				addresses[addresses.length - 1] = new NetworkAddress(host, port);
			}
			break;
			
			
			default:
				// Other elements not handled
			break;
		}
	}
	catch (Error error) {
		writefln("Got error: %s", error);
		exit(1);
	}
	catch (Exception exception) {
		writefln("Got exception: %s", exception);
		exit(1);
	}
writefln("Parsed %s", name);
	}


	void onEndElement (string name) {
		if (name == "connection") {
			// Closing a connection, create the proper SSH connection
			writefln("SSH connection through %s hop", hop);
			
			foreach (NetworkAddress address; addresses) {
				writefln("\tunnel to %s", address);
			}
		}
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
 */
class XMLParser {


	/**
	 * The SimpleXML instance being used.
	 */
	private SimpleXML simpleXML;

	
	/**
	 * The methods that the parser should be using.
	 */
	private GMarkupParser parser;
	
	
	/**
	 * Creates a new instance.
	 *
	 * Parsing is done through the method parse(xml).
	 */
	this () {

		// Register only the callbacks that have been overridden
		if (&this.onError !is &XMLParser.onError) {
			parser.error = &callbackError;
		}

		if (&this.onStartElement !is &XMLParser.onStartElement) {
			parser.startElement = &callbackStartElement;
		}

		if (&this.onEndElement !is &XMLParser.onEndElement) {
			parser.endElement = &callbackEndElement;
		}

		if (&this.onText !is &XMLParser.onText) {
			parser.text = &callbackText;
		}

		if (&this.onPassthrough !is &XMLParser.onPassthrough) {
			parser.passthrough = &callbackPassthrough;
		}

		this.simpleXML = new SimpleXML(
			cast(GMarkupParser *) &parser, 
			cast(GMarkupParseFlags) 0, 
			cast(gpointer) this, 
			cast(GDestroyNotify) null
		);
	}

	
	/**
	 * Callback that will forward all 'error' events to the handler onError.
	 */
	private static void callbackError (GMarkupParseContext *context, GError *error, gpointer userData) {
		XMLParser that = cast(XMLParser) userData;
		that.onError();
	}

	
	/**
	 * Callback that will forward all 'start element' events to the handler onStartElement.
	 */
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

		// Invoke the handler
		XMLParser that = cast(XMLParser) userData;
		that.onStartElement(element, attributes);
	}

	
	/**
	 * Callback that will forward all 'end element' events to the handler onEndElement.
	 */
	private static void callbackEndElement (
		GMarkupParseContext *context,
		gchar *elementName,
		gpointer userData,
		GError **error
	) {
		string name = Str.toString(elementName);

		// Invoke the handler
		XMLParser that = cast(XMLParser) userData;
		that.onEndElement(name);
	}


	/**
	 * Callback that will forward all 'text' events to the handler onText.
	 */
	private static void callbackText (
		GMarkupParseContext *context,
		gchar *text,
		gsize textLen,
		gpointer userData,
		GError **error
	) {
		
		string buffer = toString(text, textLen);
		
		// Invoke the handler
		XMLParser that = cast(XMLParser) userData;
		that.onText(buffer);
	}


	/**
	 * Callback that will forward all 'passthrough' events to the handler onPassthrough.
	 */
	private static void callbackPassthrough (
		GMarkupParseContext *context,
		gchar *passthroughText,
		gsize textLen,
		gpointer userData,
		GError **error
	)
	{
		string buffer = toString (passthroughText, textLen);
		
		// Invoke the handler
		XMLParser that = cast(XMLParser) userData;
		that.onPassthrough(buffer);
	}


	/**
	 * Transforms a generic C string that's not necessarily null terminated into a
	 * D string.
	 */
	private static string toString (gchar *text, gsize textLen) {
		
		// Transform the C string into a D string
		string buffer;
		buffer.length = textLen;
		for (gsize i = 0; i < textLen; ++i) {
			buffer[i] = text[i];
		}
		
		return buffer;
	}


	/**
	 * Called on error, including one set by other handlers.
	 */
	void onError () {}


	/**
	 * Called for open tags <foo bar="baz">.
	 */
	void onStartElement (string name, string [string] attributes) {}


	/**
	 * Called for close tags </foo>.
	 */
	void onEndElement (string name) {}


	/**
	 * Called for character data.
	 */
	void onText (string text) {}


	/**
	 * Called for strings that should be re-saved verbatim in this same position,
	 * but are not otherwise interpretable. At the moment this includes comments
	 * and processing instructions.
	 */
	void onPassthrough (string text) {}


	/**
	 * Parses an XML document loaded into a string.
	 */
	void parse (string xml) {
		GError *error;
		this.simpleXML.parse(xml , xml.length, &error);
	}
}
