module ddox.api;

import ddox.entities;

import std.array;
import std.format;
import std.string;
import vibe.core.log;
import vibe.data.json;


string getFunctionName(Json proto)
{
	auto n = proto.name.get!string;
	if( auto ptn = "templateName" in proto ){
		auto tn = ptn.get!string;
		if( tn.startsWith(n~"(") )
			return tn;
		return tn ~ "." ~ n;
	}
	return n;
}


bool hasChild(T)(Module mod){ return hasChild!T(mod.members); }
bool hasChild(T)(CompositeTypeDeclaration decl){ return hasChild!T(decl.members); }
bool hasChild(T)(Declaration[] decls){ foreach( m; decls ) if( cast(T)m ) return true; return false; }

T[] getChildren(T)(Module mod){ return getChildren!T(mod.members); }
T[] getChildren(T)(CompositeTypeDeclaration decl){ return getChildren!T(decl.members); }
T[] getChildren(T)(Declaration[] decls)
{
	T[] ret;
	foreach( ch; decls )
		if( auto ct = cast(T)ch )
			ret ~= ct;
	return ret;
}

T[] getDocGroups(T)(Module mod){ return getDocGroups!T(mod.members); }
T[] getDocGroups(T)(CompositeTypeDeclaration decl){ return getDocGroups!T(decl.members); }
T[] getDocGroups(T)(Declaration[] decls)
{
	T[] ret;
	DocGroup dg;
	string name;
	foreach( d; decls ){
		auto dt = cast(T)d;
		if( !dt ) continue;
		if( !dt.docGroup || dt.docGroup !is dg || dt.name != name ){
			ret ~= dt;
			dg = d.docGroup;
			name = d.name;
		}
	}
	return ret;
}

string formatType()(Type type)
{
	//logDebug("format type: %s", type);
	auto ret = appender!string();
	formatType(ret, type);
	return ret.data();
}

void formatType(R)(ref R dst, Type type)
{
	auto attribs = type.attributes;
	switch( type.kind ){
		default:
		case TypeKind.Primitive:
			if( type.typeDecl ){
				auto mn = type.typeDecl.module_.qualifiedName;
				auto qn = type.typeDecl.nestedName;
				if( qn.startsWith(mn~".") ) qn = qn[mn.length+1 .. $];
				formattedWrite(dst, "<a href=\"../%s/%s\">%s</a>", mn, qn, qn);
			} else {
				dst.put(type.typeName);
			}
			break;
		case TypeKind.Function:
		case TypeKind.Delegate:
			formatType(dst, type.returnType);
			dst.put(' ');
			dst.put(type.kind == TypeKind.Function ? "function" : "delegate");
			dst.put('(');
			foreach( size_t i, pt; type.parameterTypes ){
				if( i > 0 ) dst.put(", ");
				formatType(dst, pt);
				if( type._parameterNames[i].length ){
					dst.put(' ');
					dst.put(type._parameterNames[i]);
				}
				if( type._parameterDefaultValues[i] ){
					dst.put(" = ");
					dst.put(type._parameterDefaultValues[i].valueString);
				}
			}
			dst.put(')');
			foreach( att; attribs )
				dst.put(att);
			break;
		case TypeKind.Pointer:
			foreach( att; attribs ){
				dst.put(att);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put('*');
			foreach( att; attribs ) dst.put(')');
			break;
		case TypeKind.Array:
			foreach( att; attribs ){
				dst.put(att);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put("[]");
			foreach( att; attribs ) dst.put(')');
			break;
		case TypeKind.StaticArray:
			foreach( att; attribs ){
				dst.put(att);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			formattedWrite(dst, "[%s]", type.arrayLength);
			foreach( att; attribs ) dst.put(')');
			break;
		case TypeKind.AssociativeArray:
			foreach( att; attribs ){
				dst.put(att);
				dst.put('(');
			}
			formatType(dst, type.elementType);
			dst.put('[');
			formatType(dst, type.keyType);
			dst.put(']');
			foreach( att; attribs ) dst.put(')');
			break;
	}
}