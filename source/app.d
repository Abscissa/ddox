module app;

import ddox.ddoc;
import ddox.ddox;
import ddox.entities;
import ddox.htmlgenerator;
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
		default: showUsage(args); return 1;
		case "generate-html": return cmdGenerateHtml(args);
		case "serve-html": return cmdServeHtml(args);
		case "filter": return cmdFilterDocs(args);
	}
}

int cmdGenerateHtml(string[] args)
{
	string macrofile;
	bool moduleTree;
	getopt(args,
		//config.passThrough,
		"std-macros", &macrofile,
		"module-tree", &moduleTree);

	if( args.length < 4 ){
		showUsage(args);
		return 1;
	}

	if( macrofile.length ) setDefaultDdocMacroFile(macrofile);

	// parse the json output file
	auto docsettings = new DdoxSettings;
	auto pack = parseDocFile(args[2], docsettings);

	auto gensettings = new GeneratorSettings;
	gensettings.navPackageTree = moduleTree;
	generateHtmlDocs(Path(args[3]), pack, gensettings);

	return 0;
}

int cmdServeHtml(string[] args)
{
	string macrofile;
	bool moduleTree;
	getopt(args,
		//config.passThrough,
		"std-macros", &macrofile,
		"module-tree", &moduleTree);

	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	if( macrofile.length ) setDefaultDdocMacroFile(macrofile);

	// parse the json output file
	auto docsettings = new DdoxSettings;
	auto pack = parseDocFile(args[2], docsettings);

	// register the api routes and start the server
	auto gensettings = new GeneratorSettings;
	gensettings.navPackageTree = moduleTree;
	auto router = new UrlRouter;
	registerApiDocs(router, pack, "", gensettings);

	writefln("Listening on port 8080...");
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);

	startListening();
	return runEventLoop();
}

int cmdFilterDocs(string[] args)
{
	string[] excluded, included;
	Protection minprot = Protection.Private;
	bool justdoc = false;
	getopt(args,
		//config.passThrough,
		"ex", &excluded,
		"in", &included,
		"min-protection", &minprot,
		"only-documented", &justdoc);

	string jsonfile;
	if( args.length < 3 ){
		showUsage(args);
		return 1;
	}

	Json filterProt(Json json)
	{
		if( json.type == Json.Type.Object ){
			auto comment = json.comment.opt!string().strip();
			if( comment.empty && justdoc ) return Json.Undefined;
			
			Protection prot = Protection.Public;
			if( auto p = "protection" in json ){
				switch(p.get!string){
					default: break;
					case "private": prot = Protection.Private; break;
					case "package": prot = Protection.Package; break;
					case "protected": prot = Protection.Protected; break;
				}
			}
			if( comment == "private" ) prot = Protection.Private;
			if( prot < minprot ) return Json.Undefined;

			if( auto mem = "members" in json ){
				json.members = filterProt(*mem);
			}
		} else if( json.type == Json.Type.Array ){
			Json[] newmem;
			foreach( m; json ){
				auto mf = filterProt(m);
				if( mf.type != Json.Type.Undefined )
					newmem ~= mf;
			}
			return Json(newmem);
		}
		return json;
	}

	writefln("Reading doc file...");
	auto text = readText(args[2]);
	int line = 1;
	writefln("Parsing JSON...");
	auto json = parseJson(text, &line);

	writefln("Filtering modules...");
	Json[] dst;
	foreach( m; json ){
		if( "name" !in m ){
			writefln("No name for module %s - ignoring", m.file.opt!string);
			continue;
		}
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
		if( include ) dst ~= filterProt(m);
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
		filter
`, args[0]);
			break;
		case "serve-html":
			writefln(
`Usage: %s serve-html <ddocx-input-file>
    --std-macros=FILE      File containing DDOC macros that will be available
    --module-tree          Use a tree instead of a list for module navigation
`, args[0]);
			break;
		case "generate-html":
			writefln(
`Usage: %s generate-html <ddocx-input-file> <output-dir>
    --std-macros=FILE      File containing DDOC macros that will be available
    --module-tree          Use a tree instead of a list for module navigation
`, args[0]);
			break;
		case "filter":
			writefln(
`Usage: %s filter <ddocx-input-file> [options]
    --ex=PREFIX            Exclude modules with prefix
    --in=PREFIX            Force include of modules with prefix
    --min-protection=PROT  Remove items with lower protection level than
                           specified.
                           PROT can be: Public, Protected, Package, Private
    --only-documented      Remove undocumented entities
`, args[0]);
	}
	if( args.length < 2 ){
	} else {

	}
}