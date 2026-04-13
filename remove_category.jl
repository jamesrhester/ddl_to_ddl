using CrystalInfoFramework
using ArgParse
using DataFrames
using Dates
using URIs

excise(dictionary, category) = begin

    # Open original dictionary

    full_dictionary = DDLm_Dictionary(dictionary)
    full_head = get_head_category(full_dictionary)
    full_name = basename(dictionary)
    
    # Our importing dictionary
    
    new_dictionary = new_dict_with_boilerplate(category, full_name, full_head)
    
    # Scope of work
    
    linked_keys, non_keys = find_relevant_defs(dictionary, category)

    transfer_non_keys!(dictionary, new_dictionary, non_keys)
    transfer_keys!(dictionary, new_dictionary, linked_keys)
    transfer_cat!(dictionary, new_dictionary, category)
    
    return dictionary, new_dictionary
end

"""
    Non keys can simply be copied across
"""
transfer_non_keys!(dictionary, new_dictionary, non_keys) = begin

    for nk in non_keys
        add_definition!(new_dictionary, dictionary[nk])
        delete!(dictionary, nk)
    end
end

"""
When removing keys we have to remove them from the category
definition in the old dictionary as well.
"""
transfer_keys!(old_dictionary, new_dictionary, linked_keys) = begin
    
end

"""

Find all definitions that contain references to `category`. That
means the definition of `category`, any linked names, and the
category definitions for those names if they are keys.
"""
find_relevant_defs(dictionary, category) = begin

    # construct list of relevant definitions
    
    if haskey(dictionary, category)
        def_list = [category]
    else
        throw(error("$category not in dictionary"))
    end

    cat_key = get_keys_for_cat(dictionary, category)
    if len(cat_key) > 1
        throw(error("$category must have only one key"))
    end
    cat_key = cat_key[]
    @debug "Found key for $category: $cat_key"
    
    all_links = filter( r -> r.linked_item_id == cat_key, parent(d.block[:name])).master_id
    all_linked_keys = get_linked_keys(dictionary, cat_key)
    setdiff!(all_links, all_linked_keys)

    return linked_keys, all_links
    
end

new_dict_with_boilerplate(category, fixed_name, fixed_head) = begin

    dic_name = uppercase(category)*"_DIC"
    head_name = uppercase(category)*"_HEAD"
    now = today()

    top_boilerplate = """
#\#CIF_2.0
##################################################################
#                                                                #
#                                                                #
#                 $category dictionary                           #
#                                                                #
##################################################################
data_$dic_name

_dictionary.title           $dic_name
_dictionary.class           Attribute
_dictionary.version         1.0.0
_dictionary.date            $now
_dictionary.ddl_conformance 4.2.0
_dictionary.namespace       CifCore
_description.text
;
This dictionary adds the $category category to the imported
dictionary.
;

save_$head_name

_definition.id               $head_name
_definition.scope            Category
_definition.class            Head
_definition.update           $now
_description.text
;
    The $head_name category becomes the overarching category
    for the $category defined below.
;
    _name.category_id            $dic_name
    _name.object_id              $head_name

    _import.get
    [
         {'dupl':Ignore  'file':$fixed_dic  'mode':Full  'save':$fixed_head}
    ]
save_

"""

    return DDLm_Dictionary(cif_from_string(top_boilerplate))
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "-o", "--output"
        help = "Name of output dictionary, otherwise input with '_no_<category>.dic' appended"
        "dictionary"
        help = "Name of dictionary to convert"
        required = true
        "category"
        help = "Name of category to remove"
        required = true
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    help_text = """
    Remove a category from a dictionary.

    This program removes a category and all child keys from a dictionary,
    creating in addition a dictionary that imports the edited dictionary to
    create a logically identical dictionary.
    """
    parsed_args = parse_cmdline("help_text")
    source_dic = parsed_args["dictionary"]
    gone_cat = parsed_args["category"]
    @info "Arguments" parsed_args
    small_dic, large_dic = excise(dictionary, category)

    # And output these monsters
    outname = parsed_args["output"]
    fname = outname == nothing ? source_dic*"no_$gone_cat.dic" : outname
    outfile = open(fname,"w")
    println("#=== We have a dictionary ===#")
    @debug "Before output" result
    Base.show(outfile,MIME("text/cif"), result)
    close(outfile)

    # New importer
    outname = $category.dic
    outfile = open(fname, "w")
    Base.show(outfile, MIME("text/cif"), result)
    close(outfile)
end
