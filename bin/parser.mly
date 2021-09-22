(* Parser *)
     
%{
  open Syntax
%}

%token <string> VAR	(* x, y, abc, ... *)
%token <string> STRING	(* 'str', ... *)
%token <int> INT	(* 0, 1, 2, ...  *)

(* operators *)
%token PLUS		(* '+' *)
%token MINUS		(* '-' *)
%token ASTERISK		(* '*' *)
%token LT		(* '<' *)
%token GT		(* '>' *)
%token COL		(* ':' *)
%token DOT		(* '.' *)
%token COMMA		(* ',' *)
%token EQ		(* '=' *)
%token DELIMITER	(* '\n' *)
		       
(* Parentheses *)
%token LPAREN		(* '(' *)
%token RPAREN		(* ')' *)

(* Indentation *)
%token INDENT     
%token DEDENT     
%token BAD_DEDENT     
%token <token list> TOKENS	(* Zero or more TOKENs (NESTING THIS IS NOT ALLOWED) *)


(* reserved names *)
%token TRUE		(* "true"   *)
%token FALSE		(* "false"  *)
%token WHILE		(* "while"  *)
%token IF		(* "if"  *)
%token LAMBDA		(* "lambda" *)
%token DEF		(* "def"    *)
%token CLASS		(* "class"  *)
%token NONLOCAL		(* "nonlocal"    *)
%token RETURN		(* "return" *)

(* End of file *)
%token EOF 

(* Operator associativity *)
%nonassoc COL
%nonassoc LT GT
%left PLUS
%left ASTERISK
%left DOT
%nonassoc LPAREN


%start main
%type <Syntax.stmt> main

%%

(* Main part must end with EOF (End Of File) *)
main:
  | DELIMITER block EOF { $2 }
  | INDENT block DEDENT DELIMITER EOF { $2 }
  | BAD_DEDENT { failwith "bad dedent"} 
  | TOKENS { failwith "tokens should be exploded"}
;

(* tuple *)
tup_inner:
  | exp { [$1] }
  | exp COMMA tup_inner { $1::$3 }
;
	

(* vars inner *)
vars_inner:
  | VAR { [$1] }
  | VAR COMMA vars_inner { $1::$3 }
;
	
(* vars *)
vars:
  | LPAREN vars_inner RPAREN { $2 }
  | LPAREN RPAREN { [] } 
;
	

(* argument *)
arg_exp:
  (* (e1, ..., en) *)
  | LPAREN tup_inner RPAREN { $2 }  
  | LPAREN RPAREN { [] } 
;
  
(* expression *)
exp:
  | VAR
    { Var $1 }
    
  | INT
    { IntLit $1 }

  (* Unary minus -i *)
  | MINUS INT
    { IntLit (- $2) }
  
  | TRUE
    { BoolLit true }
    
  | FALSE
    { BoolLit false }
  
  | STRING
    { StringLit $1 }
  
  (* e1 + e2 *)
  | exp PLUS exp
    { Plus ($1, $3) }
  
  (* e1 * e2 *)
  | exp ASTERISK exp
    { Times ($1, $3) }
  
  (* e1 < e2 *)
  | exp LT exp
    { Lt ($1, $3) }    
  
  (* e1 > e2 *)
  | exp GT exp
    { Gt ($1, $3) }    

  (* lambda x1, ..., xn : { block } *)
  | LAMBDA vars_inner COL exp
     { Lambda ($2, Return $4) }

  (* application *)
  (* f (e1, ..., en) *)
  | exp arg_exp { App ($1, $2) }

  (* dot notation *)
  (* exp.var *)
  | exp DOT VAR { Access ($1, $3) }

  (* Parentheses *)
  | LPAREN exp RPAREN
    { $2 }
;

(* statement *)
stmt:
  (* f (e1, ..., en) ; *)
  | exp { Exp $1 } 

  (* Return *)
  | RETURN exp
    { Return $2 }
  
  (* Assignment *)
  | exp EQ exp
    { Assign ($1, $3) }

  (* def f (x1, ..., xn): { block } *)
  | DEF VAR vars COL INDENT block DEDENT
    { Assign (Var $2, Lambda ($3, $6)) }

  (* class MyClass: { block } *)
  | CLASS VAR COL INDENT block DEDENT
    { Assign (Var $2, Class ($2, [], $5)) }

  (* class MyClass (...): { block } *)
  | CLASS VAR vars COL INDENT block DEDENT
    { Assign (Var $2, Class ($2, $3, $6)) }

  (* while exp block *)
  | WHILE exp COL INDENT block DEDENT
   { While ($2, $5) }

  (* if exp block *)
  | IF exp COL INDENT block DEDENT
   { If ($2, $5) }

  | NONLOCAL VAR { NonLocal $2 }
;
    
(* block *)
block:       
  (* stmt1 stmt2 ... *)
  | stmt DELIMITER block
    { Seq ($1, $3) }
    
  | stmt DELIMITER { $1 }
;

