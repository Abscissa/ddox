module app;

import ddox.ddox;
import ddox.entities;
import ddox.htmlserver;
import ddox.jsonparser;

import vibe.core.core;
import vibe.core.file;
import vibe.http.router;
import vibe.http.server;
import vibe.data.json;
import std.array;
import std.file;
import std.getopt;
import std.stdio;
import std.string;


int main(string[] args)
{
	if( args.length < 2 ){
		showUsage(args);
		return 1;
	}

	switch( args[1] ){
		default: showUsage(args); return 1; break;
		case "generate-html": return generateHtml(args);
		case "serve-html": return serveHtml(args);
		case "filter": return filterDocs(args);
	}
}

int processDocs(string[] args)
{

	/*if( args.length < 3 || args.length > 4 ){
		showUsage(args);
		return 1;
	}

	auto input = args[2];
	auto output = args.length > 3 ? args[3] : "ddox.json";

	auto srctext = readText(input);
	int line = 1;
	auto dmd_json = parseJson(srctext, &line);
	
	auto proc = new DocProcessor;
	auto dldoc_json = proc.processProject(dmd_json);
	
	auto dst = appender!string();
	toPrettyJson(dst, dldoc_json);
	std.file.write(args[2], dst.data());*/

	return 0;
}

int generateHtml(string[] args)
{
	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	// parse the json output file
	auto docsettings = new DdoxSettings;
	auto pack = parseDocFile(args[2], docsettings);

	return 0;
}

int serveHtml(string[] args)
{
	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	// parse the json output file
	auto docsettings = new DdoxSettings;
	auto pack = parseDocFile(args[2], docsettings);

	// register the api routes and start the server
	auto router = new UrlRouter;
	registerApiDocs(router, pack, "");

	writefln("Listening on port 8080...");
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);

	startListening();
	return runEventLoop();
}

int filterDocs(string[] args)
{
	writefln("cmds: %s", args);
	string[] excluded, included;
	getopt(args,
		config.passThrough,
		"ex", &excluded,
		"in", &included);

	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	writefln("Exclude: %s", excluded);
	writefln("Include: %s", included);

	writefln("Reading doc file...");
	auto text = readText(args[2]);
	int line = 1;
	writefln("Parsing JSON...");
	auto json = parseJson(text, &line);

	writefln("Filtering modules...");
	Json[] dst;
	foreach( m; json ){
		auto n = m.name.get!string;
		bool include = true;
		foreach( ex; excluded )
			if( n.startsWith(ex) ){
				include = false;
				break;
			}
		foreach( inc; included )
			if( n.startsWith(inc) ){
				include = true;
				break;
			}
		if( include ) dst ~= m;
	}

	writefln("Writing filtered docs...");
	auto buf = appender!string();
	toPrettyJson(buf, Json(dst));
	std.file.write(args[2], buf.data());

	return 0;
}

Package parseDocFile(string filename, DdoxSettings settings)
{
	writefln("Reading doc file...");
	auto text = readText(filename);
	int line = 1;
	writefln("Parsing JSON...");
	auto json = parseJson(text, &line);
	writefln("Parsing docs...");
	auto ret = parseJsonDocs(json, settings);
	writefln("Finished parsing docs.");
	return ret;
}

void showUsage(string[] args)
{
	string cmd;
	if( args.length >= 2 ) cmd = args[1];

	switch(cmd){
		default:
			writefln(
`Usage: %s <COMMAND> [--help] (args...)
	
	<COMMAND> can be one of:
		generate-html
		serve-html
`, args[0]);
			break;
		case "serve-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file>
`, args[0]);
			break;
			break;
		case "generate-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file> <output-dir>
`, args[0]);
			break;
		case "filter":
			writefln(
`Usage: %s generate-html <ddocx-input-file> <output-dir> [options]
	-ex=PREFIX       Exclude modules with prefix
	-in=PREFIX       Force include of modules with prefix
`, args[0]);
	}
	if( args.length < 2 ){
	} else {

	}
}