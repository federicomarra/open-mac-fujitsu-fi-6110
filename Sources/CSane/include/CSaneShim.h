#ifndef CSANE_SHIM_H
#define CSANE_SHIM_H

#include "sane/sane.h"

/* Swift-friendly accessors for the constraint union in SANE_Option_Descriptor.
   Each returns NULL unless the descriptor's constraint_type matches. */
const SANE_Range *csane_constraint_range(const SANE_Option_Descriptor *d);
const SANE_Word *csane_constraint_word_list(const SANE_Option_Descriptor *d);
const SANE_String_Const *csane_constraint_string_list(const SANE_Option_Descriptor *d);

#endif
