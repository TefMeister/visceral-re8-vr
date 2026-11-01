// lookup.h -- a read-only look at the game's own type list while it runs (2026-11-02). praydog's RE Engine connector cannot run
// on this REFramework build (no .NET support), and Tefa's rule is: every game we mod has a connector from the start, and where
// there is none we make our own. This is the first piece of ours: write questions into
// reframework/data/visceral_re8/lookup_ask.txt, one a line, and the answers appear in lookup_answer.txt within a second:
//   part of a type name      every type whose full name holds it (up to 300)
//   member:part              every type with a method or field whose name holds it
//   type:Full.Name           that type's methods (static, return type, parameters) and fields (type, offset)
//   tree:Full.Name           the same with all its parents;  type:/tree:Full.Name/part  only the members whose name holds part
// It reads, never writes to, the game.
#pragma once

namespace vn::lookup {

void frame();   // UpdateBehavior: twice a second, a changed question file is answered

} // namespace vn::lookup
