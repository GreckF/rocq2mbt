(** Map basic Rocq datatypes to MoonBit builtins. *)

From RocqMbt Require Export MoonBit.

Extraction Language MoonBit.

Extract Inductive bool => "Bool" [ "true" "false" ].
Extract Inductive sumbool => "Bool" [ "true" "false" ].
Extract Inductive option => "Option" [ "Some" "None" ].
Extract Inductive unit => "Unit" [ "()" ].
