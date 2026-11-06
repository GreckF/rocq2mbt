(** Loads the extraction framework and registers the MoonBit target.

      From RocqMbt Require Import MoonBit.
      Extraction Language MoonBit. *)

From Corelib Require Export Extraction.
Declare ML Module "rocq-mbt.plugin".
