# CIF dictionary converter

## Introduction

The International Union of Crystallography has approved two standards for writing
CIF dictionaries (ontologies), DDL2 and DDLm. DDL2 dictionaries for macromolecular
crystallography are developed and supported by the wwPDB. DDLm dictionaries cover
the remainder of crystallographic disciplines. Some dictionaries are relevant to
both areas, such as the image CIF dictionary. Ideally it should be possible to 
automatically transform between DDL2 and DDLm versions of this dictionary so that
only one canonical version needs to be supported.  This project implements such
automatic translation.

## Installation

1. Install Julia
2. After starting Julia, install the `DrelTools` package:
```julia
using Pkg
Pkg.add("DrelTools")
```
3. Exit from the Julia interactive prompt
4. Copy the contents of the distribution directory (easy with git): `git clone https://github.com/jamesrhester/ddl_to_ddl`

## Usage

From the command line, and located in the distribution directory copied above, run:
```
julia ddl_to_ddl.jl <source_dictionary> <source_ddl>
```

This will convert `<source_dictionary>` written in DDL variant `<source_ddl>`
(which must be either `ddl2` or `ddlm`) to a version written in the other variant. The
new dictionary will have `to_<target_ddl>.dic` appended. Note that this conversion is currently
*very slow* (several minutes for the imgCIF dictionary).

Program `compare.jl` from [Julia CIF tools](https://github.com/jamesrhester/julia_cif_tools)
can be used to compare the result of round-tripping DDL2 -> DDLm -> DDL2.

## How it works

The specifications for translating the dictionary attributes are
entirely expressed in dREL.  dREL is a language for manipulating
relationally-organised data. The files `ddl2_in_ddlm.dic`,
`ddl2_extra_ddlm.dic` and `ddl2_with_methods.dic` contain these dREL
methods in the appropriate places.

In order to use dREL the relational organisation of the dictionaries
themselves must be described. In other words, the save frame contents
must be combined to form a set of tables. DDL2 is rigorously
relational in its organisation and requires no further clarification;
in the case of DDLm, `master_id` is added to all categories to refer
to the `definition.id` to which a given attribute value relates. This
is the only addition to the DDLm attribute set and only appears in
the dREL methods.

`ddl2_extra_ddlm.dic` contains additional DDLm attribute
definitions for capturing information not covered by DDL2, such as
text value construction and NeXus mapping details.
