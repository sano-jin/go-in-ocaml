(* main.ml *)

open Syntax ;;
open Eval ;;

(* parse : string -> command *)
let parse str = 
  Parser.main Lexer.token 
    (Lexing.from_string str)


(* Main.run 
"let X = 4;
 let Y = 1;
 let Z = 0;
 while (Z < X) {
   Y := 2 * Y;
   Z := Z + 1;
 }
 print Y;
"
 -> 16
*)
let run str = 
  eval_stmt [] (parse str)


(* read lines from the given file *)
let read_file name : string =
  let ic = open_in name in
  let try_read () =
    try Some (input_line ic) with End_of_file -> None in
  let rec loop acc = match try_read () with
    | Some s -> loop (s :: acc)
    | None ->
       close_in ic;
       String.concat "\n" @@ List.rev @@ "" :: acc
  in
  loop []

let (<.) f g = fun x -> f (g x)
       
let exec =
  eval_stmt [] <. parse <. read_file


(*
let () =
  match exec Sys.argv.(1) with
  | Some value -> Printf.printf "%s\n" @@ string_of_value value
  | None -> ()
 *)			     
