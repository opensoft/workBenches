#!/usr/bin/env bash

# User answers must come from stdin; data iterators use a separate descriptor.
setup_read() {
    local setup_answer setup_question="$1"
    setup_question="${setup_question%: }"
    setup_question="${setup_question%:}"
    if ! read -r -p "$setup_question (Q to cancel): " setup_answer; then exit 130; fi
    [[ "${setup_answer,,}" != q ]] || exit 130
    printf -v "$2" '%s' "$setup_answer"
}

setup_propagate_cancel() {
    case "$1" in 130|143) exit "$1" ;; esac
}
