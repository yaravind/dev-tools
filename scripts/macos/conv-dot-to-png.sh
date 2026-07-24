#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"

dot -Tpng "${0:A:h}/../assets/triples.dot" -o "${0:A:h}/../assets/triples.png"
