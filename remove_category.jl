using CrystalInfoFramework
using ArgParse
using DataFrames
using Dates

excise(full_dictionary, category) = begin

    # Scope of work
    
    linked_keys, non_keys = find_relevant_defs(full_dictionary, category)
    move_definitions!(full_dictionary, category, linked_keys, non_keys)
end

excise(full_dictionary, category, real_key) = begin

    # Scope of work
    
    linked_keys, non_keys = find_relevant_defs(full_dictionary, category, real_key)
    move_definitions!(full_dictionary, category, linked_keys, non_keys)
end

move_definitions!(full_dictionary, category, linked_keys, non_keys) = begin
    
    # Create new importing dictionary
    
    full_head = find_head_category(full_dictionary)
    full_name = basename(full_dictionary[:dictionary].uri[])
    new_dictionary = new_dict_with_boilerplate(category, full_name, full_head)

    # Transfer definitions
    
    transfer_non_keys!(full_dictionary, new_dictionary, non_keys)
    transfer_keys!(full_dictionary, new_dictionary, linked_keys)
    transfer_cat!(full_dictionary, new_dictionary, category)
    
    return full_dictionary, new_dictionary
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

    for lk in linked_keys

        # edit category definition

        cat = find_category(old_dictionary, lk)
        add_definition!(new_dictionary, old_dictionary[cat])
        remove_key!(old_dictionary, cat, lk)

        # move definition across
        add_definition!(new_dictionary, old_dictionary[lk])
        delete!(old_dictionary, lk)
    end
end

"""
   This should go to CrystalInfoFramework. Remove the keyname
   from the list of keys for catname
"""
remove_key!(dict::DDLm_Dictionary, catname, keyname) = begin
    ck = parent(dict.block[:category_key])
    filter!( row -> row.master_id != catname || row.name != keyname, ck)
    dict.block[:category_key] = groupby(ck, :master_id)
end

transfer_cat!(old_dictionary, new_dictionary, catname) = begin
    add_definition!(new_dictionary, old_dictionary[catname])

    # Does it need reparenting?

    old_parent = lowercase(old_dictionary[catname][:name].category_id[])
    old_head = find_head_category(old_dictionary)
    if old_parent == old_head
        new_dictionary[catname][:name].category_id = [find_head_category(new_dictionary)]
    end
    
    delete!(old_dictionary, catname)
    catnames = get_names_in_cat(old_dictionary, catname)
    for c in catnames
        add_definition!(new_dictionary, old_dictionary[c])
        delete!(old_dictionary, c)
    end
    
end

"""

Find all definitions that contain references to `category`. That
means the definition of `category`, any linked names, and the
category definitions for those names if they are keys, and then
all data names defined in the category itself.
"""
find_relevant_defs(d::DDLm_Dictionary, category, cat_key) = begin

    # construct list of relevant definitions
    
    if !haskey(d, category)
        throw(error("$category not in dictionary"))
    end

    all_links = filter( r -> r.linked_item_id == cat_key, parent(d.block[:name])).master_id
    all_linked_keys = get_linked_keys(d, cat_key)
    setdiff!(all_links, all_linked_keys)

    return all_linked_keys, all_links
    
end

find_relevant_defs(d::DDLm_Dictionary, category) = begin

    cat_key = get_keys_for_cat(d, category)
    if length(cat_key) > 1
        throw(error("$category must have only one key"))
    end
    cat_key = cat_key[]
    @debug "Found key for $category: $cat_key"
    find_relevant_defs(d, category, cat_key)
end

new_dict_with_boilerplate(category, fixed_name, fixed_head) = begin

    dic_name = uppercase(category)*"_DIC"
    head_name = uppercase(category)*"_HEAD"
    now = today()

    top_boilerplate = """
#\\#CIF_2.0
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
         {'dupl':Ignore  'file':$fixed_name  'mode':Full  'save':$fixed_head}
    ]
save_

"""

    return DDLm_Dictionary(cif_from_string(top_boilerplate), ignore_imports = :All)
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "-o", "--output"
        help = "Name of output dictionary, otherwise input with '_no_<category>.dic' appended"
        "-k", "--key"
        help = "Consider <key> to be the only true key for <category>"
        nargs = 1
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
    parsed_args = parse_cmdline(help_text)
    source_dic = parsed_args["dictionary"]
    gone_cat = parsed_args["category"]
    real_key = parsed_args["key"]
    @info "Arguments" parsed_args
    as_dic = DDLm_Dictionary(source_dic, ignore_imports = :All)
    chopped_dic, new_dic = real_key == [] ? excise(as_dic, gone_cat) : excise(as_dic, gone_cat, real_key[])

    # And output these monsters
    outname = parsed_args["output"]
    fname = outname == nothing ? source_dic*"no_$gone_cat.dic" : outname
    outfile = open(fname,"w")
    println("#=== We have a dictionary ===#")
    Base.show(outfile,MIME("text/cif"), chopped_dic)
    close(outfile)

    # New importer
    outname = "$gone_cat.dic"
    outfile = open(outname, "w")
    Base.show(outfile, MIME("text/cif"), new_dic)
    close(outfile)
end
