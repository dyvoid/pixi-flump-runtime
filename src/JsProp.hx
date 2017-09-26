package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.Tools;
using Lambda;

private typedef SuperClass = Null<{ t:Ref<ClassType>, params:Array<Type> }>;

class JsProp
{
	public static macro function marked() : Array<Field>
	{
		if (Context.defined("display")) return null;
		
		var klass = Context.getLocalClass().get();
		var fields = Context.getBuildFields();
		
		if (Context.defined("js"))
		{
			var codes = [];
			for (field in fields)
			{
				if (hasMeta(field, ":property"))
				{
					var t = getDefinePropertyCode(field, true, true);
					if (t != null) codes.push(t);
				}
			}
			if (codes.length > 0)
			{
				addDefinePropertyCode(fields, klass.superClass, codes);
				return fields;
			}
		}
		else
		{
			if (fields.exists(hasMeta.bind(_, ":property")))
			{
				//ensureHxSerializeFunctionExists(fields, klass.superClass);
				//ensureHxUnserializeFunctionExists(fields, klass.superClass);
				return fields;
			}
		}
		return null;
	}
	
	public static macro function all() : Array<Field>
	{
		if (Context.defined("display")) return null;
		
		var klass = Context.getLocalClass().get();
		var fields = Context.getBuildFields();
		
		if (Context.defined("js"))
		{
			var codes = [];
			for (field in fields)
			{
				switch (field.kind)
				{
					case FieldType.FProp(_, _, _, _):
						var t = getDefinePropertyCode(field, true, false);
						if (t != null) codes.push(t);
					case _:
				}
			}
			if (codes.length > 0)
			{
				addDefinePropertyCode(fields, klass.superClass, codes);
				return fields;
			}
		}
		else
		{
			if (fields.exists(function(f) return getDefinePropertyCode(f, false, false) != null))
			{
				//ensureHxSerializeFunctionExists(fields, klass.superClass);
				//ensureHxUnserializeFunctionExists(fields, klass.superClass);
				return fields;
			}
		}
		return null;
	}
	
	static function addDefinePropertyCode(fields:Array<Field>, superClass:SuperClass, codes:Array<Expr>)
	{
		var code = macro $b{codes};
		prependCode(getConstructorFunction(fields, superClass), code);
		//prependCode(getHxUnserializeFunction(fields, superClass), code);
		//ensureHxSerializeFunctionExists(fields, superClass);
	}
	
	static function getDefinePropertyCode(field:Field, fixGetterSetter:Bool, fatalNoSupported:Bool) : Expr
	{
		switch (field.kind)
		{
			case FieldType.FProp(get, set, t, e):
				var getter = "get_" + field.name;
				var setter = "set_" + field.name;
				
				switch ([ get, set, hasMeta(field, ":isVar")])
				{
					case [ "get", "set", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("default", "default", t, e);
						return macro (untyped Object).defineProperty(this, $v{field.name}, { get:function() return $i{getter}(), set:function(v) $i{setter}(v) });
						
					case [ "get", "never", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("default", "never", t, e);
						return macro (untyped Object).defineProperty(this, $v{field.name}, { get:function() return $i{getter}() });
						
					case [ "never", "set", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("never", "default", t, e);
						return macro (untyped Object).defineProperty(this, $v{field.name}, { set:function(v) $i{setter}(v) });
						
					case [ "default"|"null"|"never", "default"|"null"|"never", _ ]:
						// nothing to do
						
					case _:
						if (fatalNoSupported) Context.fatalError("JsProp: unsupported get/set combination. Supported: (get,set), (get,never) and (never,set) all without @:isVar.", field.pos);
				}
				
			case _:
				if (fatalNoSupported) Context.fatalError("JsProp: unsupported type (must be a property).", field.pos);
		}
		return null;
	}
	
	static function prependCode(f:Function, code:Expr)
	{
		switch (f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift({ expr:code.expr, pos:code.pos });
				
			case _:
				f.expr = macro { $code; ${f.expr}; };
		}
	}
	
	static function getConstructorFunction(fields:Array<Field>, superClass:SuperClass) : Function
	{
		var method : Field = null;
		
		for (field in fields) if (field.name == "new") { method = field; break; }
		
		if (method == null)
		{
			var superField = findSuperConstructor(superClass);
			if (superField != null)
			{
				var superFuncArgs = getClassMethodArgs(superField);
				var superCall = ECall(macro super, superFuncArgs.map(function(p) return macro $i{p.name}));
				method = createMethod(superField.isPublic, "new", superFuncArgs, macro:Void, { expr:superCall, pos:Context.currentPos() } );
			}
			else
			{
				method = createMethod(false, "new", [], macro:Void, macro {});
			}
			
			fields.push(method);
		}
		
		switch (method.kind)
		{
			case FieldType.FFun(f):
				return f;
				
			case _:
				Context.fatalError("JsProp: unexpected constructor type '" + method.kind + "'.", method.pos);
				return null;
		}
	}
	
	static function hasMeta(f:{ meta:Metadata }, m:String) : Bool
	{
		if (f.meta == null) return false;
		for (mm in f.meta)
		{
			if (mm.name == m) return true;
		}
		return false;
	}
	
	static function createMethod(isPublic:Bool, name:String, args:Array<FunctionArg>, ret:Null<ComplexType>, expr:Expr) : Field
	{
		return
		{
			  name: name
			, access: [ isPublic ? Access.APublic : Access.APrivate ]
			, kind: FieldType.FFun({ args:args, ret:ret, expr:expr, params:[] })
			, pos: expr.pos
		};
	}
	
	static function getClassMethodArgs(field:ClassField) : Array<FunctionArg>
	{
		switch (field.type)
		{
			case Type.TFun(args, ret): return args.map(toFunctionArg);
			case Type.TLazy(f):
				switch (f())
				{
					case Type.TFun(args, ret): return args.map(toFunctionArg);
					case _:
				}
			case _:
		}
		Context.fatalError("Expected TFun: " + field.type, field.pos);
		return null;
	}
	
	static function toFunctionArg(a:{ name:String, opt:Bool, t:Type }) : FunctionArg
	{
		return { name: a.name, opt: a.opt, type: a.t.toComplexType(), value: null };
	}
	
	static function ensureNoExpr(e:Null<Expr>, pos:Position)
	{
		if (e != null)
		{
			Context.fatalError("Default value is not supported here.", pos);
		}
	}
	
	static function findSuperConstructor(superClass:SuperClass) : ClassField
	{
		if (superClass == null) return null;
		if (superClass.t.get().constructor != null) return superClass.t.get().constructor.get();
		return findSuperConstructor(superClass.t.get().superClass);
	}
}
