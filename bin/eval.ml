(* eval.ml *)

open Syntax
open Util

(** some helper functions *)
let extract_int = function
  | IntVal i -> i
  | _ -> failwith @@ "type error. expected int"

let extract_class_variables_ref obj_fields_ref =
  match !(List.assoc "__class__" !obj_fields_ref) with
  | ObjectVal class_fields -> class_fields
  | _ -> failwith @@ "__class__ is expected to be an object"

let extract_class_variable_opt obj_fields_ref prop =
  List.assoc_opt prop !(extract_class_variables_ref obj_fields_ref)

(** The evaluator *)
let rec eval_exp envs exp =
  let eval_binop f e1 e2 = f (eval_exp envs e1) (eval_exp envs e2) in
  let eval_binop_int f =
    eval_binop (fun v1 v2 -> f (extract_int v1) (extract_int v2))
  in
  match exp with
  | Var var -> (
      match one_of (List.assoc_opt var <. ( ! )) envs with
      | Some v -> !v
      | None -> failwith @@ "unbound variable " ^ var)
  | IntLit num -> IntVal num
  | BoolLit bool -> BoolVal bool
  | StringLit str -> StringVal str
  | Plus (e1, e2) -> IntVal (eval_binop_int ( + ) e1 e2)
  | Times (e1, e2) -> IntVal (eval_binop_int ( * ) e1 e2)
  | Lt (e1, e2) -> BoolVal (eval_binop_int ( < ) e1 e2)
  | Gt (e1, e2) -> BoolVal (eval_binop_int ( > ) e1 e2)
  | Lambda (args, body) -> LambdaVal (args, body, envs)
  | App (f, args) -> (
      match (f, List.map (eval_exp envs) args) with
      | Var "object", [] -> ObjectVal (ref [ ("__class__", ref VoidVal) ])
      | Var "copy", [ ObjectVal dict ] ->
          ObjectVal (ref @@ List.map (second (ref <. ( ! ))) !dict)
      | Var "print", argVals ->
          print_endline @@ String.concat " " @@ List.map string_of_value argVals;
          VoidVal
      | _, argVals -> (
          match eval_exp envs f with
          | LambdaVal (vars, body, envs') ->
              let argVals = List.map ref argVals in
              let new_env = ref @@ List.combine vars argVals in
              Either.fold ~left:(const VoidVal) ~right:id
              @@ eval_stmt ([], new_env :: envs') body
          | _ -> failwith @@ "expected function type"))
  | Access (obj, prop) -> (
      match eval_exp envs obj with
      | ObjectVal dict -> (
          match List.assoc_opt prop !dict with
          | Some prop_ref -> !prop_ref
          | None -> !(Option.get @@ extract_class_variable_opt dict prop))
      | _ -> failwith @@ "Cannot access to a non-object with a dot notation")
  | Class (name, body) -> (
      let env = ref [] in
      env :=
        [
          ("__name__", ref @@ StringVal name);
          ("__init__", ref @@ LambdaVal ([], Skip, env :: envs));
        ];
      match eval_stmt ([], env :: envs) body with
      | Either.Right _ -> failwith @@ "cannot return in class definition"
      | Either.Left _ ->
          let init_vars =
            match !(List.assoc "__init__" !env) with
            | LambdaVal (_ :: vars, _, _) -> vars
            | _ ->
                failwith
                  "__init__ should be function type with zero or more arguments"
          in
          let classify_methods (var, value) =
            match !value with
            | LambdaVal (self_var :: vars, body, _) ->
                Either.Left
                  (var, Lambda ([ self_var ], Return (Lambda (vars, body))))
            | _ -> Either.Right (var, value)
          in
          let seq_of_list =
            List.fold_left (fun acc stmt -> Seq (acc, stmt)) Skip
          in
          let methods, variables = List.partition_map classify_methods !env in
          let method_binding_stmt_of (var, lambda) =
            Assign (Access (Var "self", var), App (lambda, [ Var "self" ]))
          in
          let stmts =
            [
              Assign (Var "self", App (Var "object", []));
              Assign (Access (Var "self", "__class__"), Var "__class__");
            ]
            @ List.map method_binding_stmt_of methods
            @ [
                Exp
                  (App
                     ( Access (Var "self", "__init__"),
                       List.map (fun var -> Var var) init_vars ));
                Return (Var "self");
              ]
          in
          LambdaVal
            ( init_vars,
              seq_of_list stmts,
              ref [ ("__class__", ref (ObjectVal (ref variables))) ] :: envs ))

and eval_stmt (nonlocals, envs) stmt =
  let proceed = Either.Left nonlocals in
  let assign envs var v =
    let assignable_envs =
      match envs with
      | [] -> failwith "there should be at least the global environment"
      | [ _ ] -> envs
      | env :: _ -> if List.mem var nonlocals then dropLast1 envs else [ env ]
    in
    (match one_of (List.assoc_opt var <. ( ! )) assignable_envs with
    | None ->
        let env = List.hd envs in
        env := (var, ref v) :: !env
    | Some old_ref -> old_ref := v);
    proceed
  in
  match stmt with
  | Assign (Var var, e) -> assign envs var @@ eval_exp envs e
  | Assign (Access (obj, prop), exp) -> (
      let obj = eval_exp envs obj in
      let value = eval_exp envs exp in
      match obj with
      | ObjectVal dict ->
          (match List.assoc_opt prop !dict with
          | Some prop -> prop := value
          | None -> dict := (prop, ref value) :: !dict);
          proceed
      | LambdaVal (_, _, variables_ref :: _) ->
          (let class_variables_ref =
             extract_class_variables_ref variables_ref
           in
           match List.assoc_opt prop !class_variables_ref with
           | Some prop -> prop := value
           | None ->
               class_variables_ref := (prop, ref value) :: !class_variables_ref);
          proceed
      | _ -> failwith @@ "Cannot access to a non-object with a dot notation")
  | Assign (_, _) -> failwith @@ "cannot assign to operator"
  | NonLocal var -> Either.Left (var :: nonlocals)
  | Exp e ->
      ignore @@ eval_exp envs e;
      proceed
  | Seq (s1, s2) -> (
      match eval_stmt (nonlocals, envs) s1 with
      | Either.Left nonlocals -> eval_stmt (nonlocals, envs) s2
      | otherwise -> otherwise)
  | While (cond, stmt) -> (
      match eval_exp envs cond with
      | BoolVal true ->
          eval_stmt (nonlocals, envs) @@ Seq (stmt, While (cond, stmt))
      | BoolVal false -> proceed
      | _ -> failwith @@ "expected boolean value")
  | If (cond, stmt) -> (
      match eval_exp envs cond with
      | BoolVal true -> eval_stmt (nonlocals, envs) stmt
      | BoolVal false -> proceed
      | _ -> failwith @@ "expected boolean value")
  | Skip -> proceed
  | Return e -> Either.Right (eval_exp envs e)
