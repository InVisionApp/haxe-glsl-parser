/*
	Parser

	LALR parser based on lemon parser generator
	Lemon was written by D. Richard Hipp and is maintained as part of the SQLite project
	http://www.hwaci.com/sw/lemon/
	
	Haxe port:
	@author George Corney
*/

package glsl.parse;

import glsl.parse.Actions.MinorType;

import glsl.lex.Tokenizer;

class Parser{
	
	//state machine variables
	static public var warnings:Array<String>;

	static var i:Int; //stack index
	static var stack:Stack;
	static var errorCount:Int;

	static var currentMinor:MinorType;

	static var preprocess = true;

	static function init(){
		//init state machine
		i = 0;
		stack = [{
			stateno: 0,
			major: 0,
			minor: null
		}];
		errorCount = 0;
		currentMinor = null;
		warnings = [];
		Actions.init();
	}

	static public function parse(input:String){
		var tokens = Tokenizer.tokenize(input);
		return parseTokens(tokens);
	}

	static public function parseTokens(tokens:Array<Token>){
		init();
		
		//for each token, execute parseStep
		var lastToken = null;
		for(t in tokens){
			if(ignoredTokens.indexOf(t.type) != -1) continue;

			t = Actions.processToken(t);

			parseStep(tokenIdMap.get(t.type), t);
			lastToken = t;
		}

		//eof step
		parseStep(0, lastToken); //using the lastToken for the EOF step allows better error reporting if it fails

		return currentMinor;
	}

	//for each token, major = tokenId
	static function parseStep(major:Int, minor:MinorType){		
		var act:Int, 
			atEOF:Bool = (major == 0),
			errorHit:Bool = false;

		do{
			act = findShiftAction(major);

			if(act < nStates){
				assert( !atEOF );

				shift(act, major, minor); //push a leaf/token to the stack
				errorCount--;
				major = illegalSymbolNumber;
			}else if(act < nStates + nRules){
				reduce(act - nStates);
			}else{
				//syntax error
				assert( act == errorAction );
				if(errorRecovery){
					//@! error recovery code if the error symbol in the grammar is supported
				}else{
					if(errorCount <= 0){
						syntaxError(major, minor);
					}

					errorCount = 3;
					if( atEOF ){
						parseFailed(minor);
					}
					major = illegalSymbolNumber;
				}
			}

			
		}while( major != illegalSymbolNumber && i >= 0);
	}

	static function popStack(){
		if(i < 0) return 0;
		var major = stack.pop().major;
		i--;
		return major;
	}

	//Find the appropriate action for a parser given the terminal
	//look-ahead token iLookAhead.
	static function findShiftAction(iLookAhead:Int){
		var stateno = stack[i].stateno;
		var j:Int = shiftOffset[stateno];

		if(stateno > shiftCount || j == shiftUseDefault){
			return defaultAction[stateno];
		}

		assert(iLookAhead != illegalSymbolNumber);

		j += iLookAhead;

		if(j < 0 || j >= actionCount || lookahead[j] != iLookAhead){
			return defaultAction[stateno];
		}

		return action[j];
	}

	//Find the appropriate action for a parser given the non-terminal
	//look-ahead token iLookAhead.
	static function findReduceAction(stateno:Int, iLookAhead:Int){
		var j:Int;

		if(errorRecovery){
			if(stateno > reduceCount) return defaultAction[stateno];
		}else{
			assert( stateno <= reduceCount);
		}

		j = reduceOffset[stateno];

		assert( j != reduceUseDefault );
		assert( iLookAhead != illegalSymbolNumber );
		j += iLookAhead;

		if(errorRecovery){
			if( j < 0 || j >= actionCount || lookahead[j] != iLookAhead ){
				return defaultAction[stateno];
			}
		}else{
			assert( j >= 0 && j < actionCount );
			assert( lookahead[j] == iLookAhead );
		}

		return action[j];
	}

	static function shift(newState:Int, major:Int, minor:MinorType){
		i++;
		stack[i] = {
			stateno: newState,
			major: major,
			minor: minor
		};
	}

	static function reduce(ruleno:Int){
		var goto:Int;               //next state
		var act:Int;                //next action
		var size:Int;               //amount to pop the stack

		//new node generated after reducing with this rule
		var newNode = Actions.reduce(ruleno); //trigger custom reduce behavior
		currentMinor = newNode;

		goto = ruleInfo[ruleno].lhs;
		size = ruleInfo[ruleno].nrhs;
		i -= size;

		act = findReduceAction(stack[i].stateno, goto);

		if(act < nStates){
			shift(act, goto, newNode); //push a node (the result of a rule) to the stack
		}else{
			assert( act == nStates + nRules + 1);
			accept();
		}
	}

	static function accept(){
		while(i >= 0) popStack();
	}

	static inline function syntaxError(major:Int, minor:MinorType){
		var msg = 'syntax error';

		var data = Reflect.field(minor, 'data');
		if(data != null) msg += ', \'$data\'';

		warn(msg, minor);
	}//@! needs improving

	static inline function parseFailed(minor:MinorType){
		var msg = 'parse failed';
		
		var data = Reflect.field(minor, 'data');
		if(data != null) msg += ', \'$data\'';

		error(msg, minor);
	}

	//Utils
	static function assert(cond:Bool, ?pos:haxe.PosInfos)
		if(!cond) warn('assert failed in ${pos.className}::${pos.methodName} line ${pos.lineNumber}');

	//Error Reporting
	static function warn(msg, ?info:Dynamic){
		var str = 'Parser Warning: $msg';

		var line = Reflect.field(info, 'line');
		var col = Reflect.field(info, 'column');
		if(Type.typeof(line).equals(Type.ValueType.TInt)){
			str += ', line $line';
			if(Type.typeof(col).equals(Type.ValueType.TInt)){
				str += ', column $col';
			}
		}

		warnings.push(str);
	}

	static function error(msg, ?info:Dynamic){
		var str = 'Parser Error: $msg';

		var line = Reflect.field(info, 'line');
		var col = Reflect.field(info, 'column');
		if(Type.typeof(line).equals(Type.ValueType.TInt)){
			str += ', line $line';
			if(Type.typeof(col).equals(Type.ValueType.TInt)){
				str += ', column $col';
			}
		}

		throw str;
	}

	//Language Data & Parser Settings
	static inline var errorRecovery:Bool       = Tables.errorRecovery;
	//consts
	static inline var illegalSymbolNumber:Int = Tables.illegalSymbolNumber;

	static inline var nStates                 = Tables.nStates;
	static inline var nRules                  = Tables.nRules;
	static inline var noAction                = nStates + nRules + 2;
	static inline var acceptAction            = nStates + nRules + 1;
	static inline var errorAction             = nStates + nRules;

	//tables
	static var actionCount                    = Tables.actionCount;
	static var action:Array<Int>              = Tables.action;
	static var lookahead:Array<Int>           = Tables.lookahead;

	static inline var shiftUseDefault         = Tables.shiftUseDefault;
	static inline var shiftCount              = Tables.shiftCount;
	static inline var shiftOffsetMin          = Tables.shiftOffsetMin;
	static inline var shiftOffsetMax          = Tables.shiftOffsetMax;
	static var shiftOffset:Array<Int>         = Tables.shiftOffset;

	static inline var reduceUseDefault        = Tables.reduceUseDefault;
	static inline var reduceCount             = Tables.reduceCount;
	static inline var reduceMin               = Tables.reduceMin;
	static inline var reduceMax               = Tables.reduceMax;
	static var reduceOffset:Array<Int>        = Tables.reduceOffset;

	static var defaultAction:Array<Int>       = Tables.defaultAction;

	//rule info table
	static var ruleInfo:Array<RuleInfoEntry>  = Tables.ruleInfo;

	//tokenId
	static var tokenIdMap:Map<TokenType, Int> = Tables.tokenIdMap;

	//skip-over tokens
	static var ignoredTokens:Array<TokenType> = Tables.ignoredTokens;
}

abstract RuleInfoEntry(Array<Int>) from Array<Int> {
	public var lhs(get, set):Int;
	public var nrhs(get, set):Int;
	
	function get_lhs()return this[0];
	function set_lhs(v:Int)return this[0] = v;
	function get_nrhs()return this[1];
	function set_nrhs(v:Int)return this[1] = v;
}

typedef StackEntry = {
	var stateno:Int;
	var major:Int;
	var minor:MinorType;
}

typedef Stack = Array<StackEntry>;