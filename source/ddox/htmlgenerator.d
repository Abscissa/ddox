/**
	Generates offline documentation in the form of HTML files.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module ddox.htmlgenerator;

import ddox.api;
import ddox.entities;
import ddox.settings;

import std.array;
import std.format : formattedWrite;
import std.string : startsWith, toLower;
import std.variant;
import vibe.core.log;
import vibe.core.file;
import vibe.core.stream;
import vibe.inet.path;
import vibe.http.server;
import vibe.templ.diet;


/*
	structure:
	/index.html
	/pack1/pack2/module1.html
	/pack1/pack2/module1/member.html
	/pack1/pack2/module1/member.submember.html
*/

void generateHtmlDocs(Path dst_path, Package root, GeneratorSettings settings = null)
{
	if( !settings ) settings = new GeneratorSettings;

	string linkTo(Entity ent, size_t level)
	{
		auto dst = appender!string();

		if( level ) foreach( i; 0 .. level ) dst.put("../");
		else dst.put("./");

		if( ent !is null ){
			if( !ent.parent ){
				dst.put("index.html");
				return dst.data();
			}

			auto dp = cast(VariableDeclaration)ent;
			auto dfn = ent.parent ? cast(FunctionDeclaration)ent.parent : null;
			if( dp && dfn ) ent = ent.parent;

			Entity[] nodes;
			size_t mod_idx = 0;
			while( ent ){
				if( cast(Module)ent ) mod_idx = nodes.length;
				nodes ~= ent;
				ent = ent.parent;
			}
			foreach_reverse(i, n; nodes[mod_idx .. $-1]){
				dst.put(n.name);
				if( i > 0 ) dst.put('/');
			}
			if( mod_idx == 0 ) dst.put(".html");
			else {
				dst.put('/');
				foreach_reverse(n; nodes[0 .. mod_idx]){
					dst.put(n.name);
					dst.put('.');
				}
				dst.put("html");
			}

			if( dp && dfn ){
				dst.put('#');
				dst.put(dp.name);
			}
		}

		return dst.data();
	}

	void visitDecl(Module mod, Declaration decl, Path path)
	{
		if( auto ctd = cast(CompositeTypeDeclaration)decl ){
			foreach( m; ctd.members )
				visitDecl(mod, m, path);
		} else if( auto td = cast(TemplateDeclaration)decl ){
			foreach( m; td.members )
				visitDecl(mod, m, path);
		}

		auto file = openFile(path ~ PathEntry(decl.nestedName~".html"), FileMode.createTrunc);
		scope(exit) file.close();
		generateDeclPage(file, root, mod, decl, settings, ent => linkTo(ent, path.length-dst_path.length));
	}

	void visitModule(Module mod, Path pack_path)
	{
		auto modpath = pack_path ~ PathEntry(mod.name);
		if( !existsFile(modpath) ) createDirectory(modpath);
		foreach( decl; mod.members ) visitDecl(mod, decl, modpath);
		logInfo("Generating module: %s", mod.qualifiedName);
		auto file = openFile(pack_path ~ PathEntry(mod.name~".html"), FileMode.createTrunc);
		scope(exit) file.close();
		generateModulePage(file, root, mod, settings, ent => linkTo(ent, pack_path.length-dst_path.length));
	}

	void visitPackage(Package p, Path path)
	{
		auto packpath = p.parent ? path ~ PathEntry(p.name) : path;
		if( !packpath.empty && !existsFile(packpath) ) createDirectory(packpath);
		foreach( sp; p.packages ) visitPackage(sp, packpath);
		foreach( m; p.modules ) visitModule(m, packpath);
	}

	dst_path.normalize();

	if( !dst_path.empty && !existsFile(dst_path) ) createDirectory(dst_path);

	{
		auto idxfile = openFile(dst_path ~ PathEntry("index.html"), FileMode.createTrunc);
		scope(exit) idxfile.close();
		generateApiIndex(idxfile, root, settings, ent => linkTo(ent, 0));
	}

	{
		auto symfile = openFile(dst_path ~ "symbols.js", FileMode.createTrunc);
		scope(exit) symfile.close();
		generateSymbolsJS(symfile, root, settings, ent => linkTo(ent, 0));
	}

	{
		auto smfile = openFile(dst_path ~ PathEntry("sitemap.xml"), FileMode.createTrunc);
		scope(exit) smfile.close();
		generateSitemap(smfile, root, settings, ent => linkTo(ent, 0));
	}

	visitPackage(root, dst_path);
}

class DocPageInfo {
	string delegate(Entity ent) linkTo;
	GeneratorSettings settings;
	Package rootPackage;
	Entity node;
	
	@property NavigationType navigationType() const { return settings.navigationType; }
	string formatType(Type tp, bool include_code_tags = true) { return .formatType(tp, linkTo, include_code_tags); }
	string formatDoc(DocGroup group, int hlevel, bool delegate(string) display_section)
	{
		return group.comment.renderSections(new DocGroupContext(group, linkTo), display_section, hlevel);
	}
}

class DocModulePageInfo : DocPageInfo {
	Module mod;
}

class DocDeclPageInfo : DocModulePageInfo {
	Declaration item;
	DocGroup docGroup;
	DocGroup[] docGroups; // for multiple doc groups with the same name
}

void generateSitemap(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	dst.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
	dst.write("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
	
	void writeEntry(string[] parts...){
		dst.write("<url><loc>");
		foreach( p; parts )
			dst.write(p);
		dst.write("</loc></url>\n");
	}

	void writeEntityRec(Entity ent){
		import std.string;
		if( !cast(Package)ent || ent is root_package ){
			auto link = link_to(ent);
			if( indexOf(link, '#') < 0 ) // ignore URLs with anchors
				writeEntry((settings.siteUrl ~ Path(link)).toString());
		}
		ent.iterateChildren((ch){ writeEntityRec(ch); return true; });
	}

	writeEntityRec(root_package);
	
	dst.write("</urlset>\n");
	dst.flush();
}

void generateSymbolsJS(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to)
{
	bool[string] visited;

	void writeEntry(Entity ent) {
		if (cast(Package)ent || cast(TemplateParameterDeclaration)ent) return;
		if (ent.qualifiedName in visited) return;
		visited[ent.qualifiedName] = true;

		string kind = ent.classinfo.name.split(".")[$-1].toLower;
		string[] attributes;
		if (auto fdecl = cast(FunctionDeclaration)ent) attributes = fdecl.attributes;
		else if (auto adecl = cast(AliasDeclaration)ent) attributes = adecl.attributes;
		else if (auto tdecl = cast(TypedDeclaration)ent) attributes = tdecl.type.attributes;
		attributes = attributes.map!(a => a.startsWith("@") ? a[1 .. $] : a).array;
		dst.formattedWrite(`{name: "%s", kind: "%s", path: "%s", attributes: %s},`, ent.qualifiedName, kind, link_to(ent), attributes);
		dst.put('\n');
	}

	void writeEntryRec(Entity ent) {
		writeEntry(ent);
		if (cast(FunctionDeclaration)ent) return;
		ent.iterateChildren((ch) { writeEntryRec(ch); return true; });
	}

	dst.write("// symbol index generated by DDOX - do not edit\n");
	dst.write("var symbols = [\n");
	writeEntryRec(root_package);
	dst.write("];\n");
}

void generateApiIndex(OutputStream dst, Package root_package, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	auto info = new DocPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.node = root_package;

	dst.parseDietFileCompat!("ddox.overview.dt",
		HTTPServerRequest, "req",
		DocPageInfo, "info")
		(Variant(req), Variant(info));
}

void generateModulePage(OutputStream dst, Package root_package, Module mod, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	auto info = new DocModulePageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.mod = mod;
	info.node = mod;

	dst.parseDietFileCompat!("ddox.module.dt",
		HTTPServerRequest, "req",
		DocModulePageInfo, "info")
		(Variant(req), Variant(info));
}

void generateDeclPage(OutputStream dst, Package root_package, Module mod, Declaration item, GeneratorSettings settings, string delegate(Entity) link_to, HTTPServerRequest req = null)
{
	auto info = new DocDeclPageInfo;
	info.linkTo = link_to;
	info.settings = settings;
	info.rootPackage = root_package;
	info.node = item;
	info.mod = mod;
	info.item = item;
	info.docGroup = item.docGroup;
	info.docGroups = docGroups(mod.lookupAll!Declaration(item.nestedName));

	switch( info.item.kind ){
		default: logWarn("Unknown API item kind: %s", item.kind); return;
		case DeclarationKind.Variable:
		case DeclarationKind.EnumMember:
		case DeclarationKind.Alias:
			dst.parseDietFileCompat!("ddox.variable.dt", HTTPServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Function:
			dst.parseDietFileCompat!("ddox.function.dt", HTTPServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Interface:
		case DeclarationKind.Class:
		case DeclarationKind.Struct:
		case DeclarationKind.Union:
			dst.parseDietFileCompat!("ddox.composite.dt", HTTPServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Template:
			dst.parseDietFileCompat!("ddox.template.dt", HTTPServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
		case DeclarationKind.Enum:
			dst.parseDietFileCompat!("ddox.enum.dt", HTTPServerRequest, "req", DocDeclPageInfo, "info")(Variant(req), Variant(info));
			break;
	}
}
