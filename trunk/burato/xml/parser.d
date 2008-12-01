/*
 * xml/parser.d - Object oriented parser based on glib.SimpleXML
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

module burato.xml.parser;

/**
 * This module provides an XML parser that's based on glib.SimpleXML. This
 * parser provides an object oriented interface to SimpleXML. The methods are
 * also using D based arguments instead of based C arguments used by SimpleXML.
 */

private import std.string;

private import glib.SimpleXML;
private import glib.Str;


/**
 * Basic XML Parser (a pseudo SAX parser) that's based on SimpleXML. This parser
 * is object oriented and relies on methods instead of functions.
 *
 * The parser can be overloaded by defining the following methods:
 *
 *  onError - called when an error is encoutered
 *  onStartElement - called when an element is started
 *  onEndElement - called when an element is ended
 *  onText - called when text is being processed
 *  onPassthrough - called when non text data (PI, comments) is being processed
 *  
 * The method parse(xml) can be used to parse an XML string.
 *
 * This class gives a more object oriented interface to SimpleXML, futhermore it
 * also makes the methods look more 'D' as it uses 'D' types for the method
 * arguments.
 */
public class XMLParser {


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
	public this () {

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
	extern (C) private static void callbackError (GMarkupParseContext *context, GError *error, gpointer userData) {
		XMLParser that = cast(XMLParser) userData;
		that.onError();
	}

	
	/**
	 * Callback that will forward all 'start element' events to the handler onStartElement.
	 */
	extern (C) private static void callbackStartElement (
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
	extern (C) private static void callbackEndElement (
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
	extern (C) private static void callbackText (
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
	extern (C) private static void callbackPassthrough (
		GMarkupParseContext *context,
		gchar *passthroughText,
		gsize textLen,
		gpointer userData,
		GError **error
	)
	{
		string buffer = toString(passthroughText, textLen);
		
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
	protected void onError () {}


	/**
	 * Called for open tags <foo bar="baz">.
	 */
	protected void onStartElement (string name, string [string] attributes) {}


	/**
	 * Called for close tags </foo>.
	 */
	protected void onEndElement (string name) {}


	/**
	 * Called for character data. Note: this method could be called multiple
	 * times for a tag (element), the text is not null terminated.
	 */
	protected void onText (string text) {}


	/**
	 * Called for strings that should be re-saved verbatim in this same position,
	 * but are not otherwise interpretable. At the moment this includes comments
	 * and processing instructions.
	 */
	protected void onPassthrough (string text) {}


	/**
	 * Parses an XML document loaded into a string.
	 */
	public void parse (string xml) {
		this.simpleXML.parse(xml , xml.length);
	}
}
