#include "CSaneShim.h"
#include <stddef.h>

const SANE_Range *csane_constraint_range(const SANE_Option_Descriptor *d) {
    return d->constraint_type == SANE_CONSTRAINT_RANGE ? d->constraint.range : NULL;
}

const SANE_Word *csane_constraint_word_list(const SANE_Option_Descriptor *d) {
    return d->constraint_type == SANE_CONSTRAINT_WORD_LIST ? d->constraint.word_list : NULL;
}

const SANE_String_Const *csane_constraint_string_list(const SANE_Option_Descriptor *d) {
    return d->constraint_type == SANE_CONSTRAINT_STRING_LIST ? d->constraint.string_list : NULL;
}
