# A program to translate the imgCIF dictionary to DDLm

using CrystalInfoFramework
using CrystalInfoContainers
using DrelTools
using ArgParse
using DataFrames
using Dates
using URIs

#
# There are plain versions to avoid a cycle of derivations pinballing between ddl2
# and ddlm methods
#
const ddl2_trans_dic = DDL2_Dictionary(joinpath(@__DIR__,"ddl2_with_methods.dic"))
const ddlm_trans_dic = DDLm_Dictionary(joinpath(@__DIR__,"ddl2_extra_ddlm.dic"))
const ddl2_plain_dic = DDL2_Dictionary(joinpath(@__DIR__,"ddl_core_2.1.3.dic"))

"""
Load a dictionary as a data source.  We return the dictionary interpretation as well
to make use of high-level information
"""
load_dictionary_as_data(::Type{DDL2_Dictionary}, filename) = begin
    ddl2dic = DDL2_Dictionary(filename)
    return TypedDataSource(as_data(ddl2dic), ddl2_trans_dic), ddl2dic
end    

load_dictionary_as_data(::Type{DDLm_Dictionary}, filename) = begin
    ddlmdic = DDLm_Dictionary(filename, ignore_imports=:Full)
    return TypedDataSource(as_data(ddlmdic), ddlm_trans_dic), ddlmdic
end    

force_translate(category_holder,to_namespace) = begin
    trans_dic = get_dictionary(category_holder,to_namespace)
    all_cats = get_categories(trans_dic, head = false)    
    for one_cat in all_cats
        println("# Attempting to translate $one_cat\n")
        try
            va = get_category(category_holder,one_cat,to_namespace)
        catch e
            if e isa KeyError
                println("$e but continuing")
                continue
            end
            rethrow()
        end
        println("# Now doing individual items\n")
        all_items = get_names_in_cat(trans_dic,one_cat)
        for one_item in all_items
            print("# Translating $one_item...")
            try
                va = category_holder[one_item,to_namespace]
            catch e
                if e isa KeyError
                    print("nothing\n")
                    continue
                end
                rethrow()
            end
            print("Success\n")
        end
    end

    println( "#== End of translation ==#")
end

prepare_data(input_dict,to_namespace) = begin
    if to_namespace == "ddlm"
        dictype = DDL2_Dictionary
        att_ref = ddl2_plain_dic
        other_ref = ddlm_trans_dic
    elseif to_namespace == "ddl2"
        dictype = DDLm_Dictionary
        remove_methods!(ddlm_trans_dic)
        att_ref = ddlm_trans_dic
        other_ref = ddl2_trans_dic
    end
    dic_datasource, as_dic = load_dictionary_as_data(dictype, input_dict)
    category_holder = DynamicDDLmRC(dic_datasource, att_ref)
    # add our target dictionary as well
    category_holder.dict[to_namespace] = other_ref 
    category_holder.value_cache[to_namespace] = Dict{String,Any}()
    category_holder.cat_cache[to_namespace] = Dict{String,CifCategory}()
    return category_holder,as_dic
end

"""
    Append `message` to the latest version information in dictionary_audit
"""
add_audit_message!(d::DDLm_Dictionary, message) = begin

    version = d[:dictionary].version[]
    audit = d[:dictionary_audit].version
    audit_row = indexin([version], audit)[]
    @debug "Adding '$message' to $version" audit_row
    d[:dictionary_audit].date[audit_row] = "$(today())"
    d[:dictionary].date = ["$(today())"]
    d[:dictionary_audit].revision[audit_row] *= "\n     $message\n"
end

"""
    align_set_cats(proto_dict,reference_dict)

Make all categories common to `proto_dict` and `reference_dict` 
match Set/Loop by changing `proto_dict` accordingly.

"""
align_set_cats(proto_dict::DDLm_Dictionary,reference_dict::DDLm_Dictionary) = begin
    pd_cats = get_categories(proto_dict, head = false)
    common_set_cats = intersect(pd_cats,get_set_categories(reference_dict))
    @debug "Common set cats: $common_set_cats"
    for cs in common_set_cats
        update_dict!(proto_dict,cs,"_definition.class","Set")
        update_dict!(proto_dict,cs,"_definition.update","$(today())")
    end

    # If we have added a definition, update dictionary date and audit message as well
    if length(common_set_cats) > 0
        proto_dict[:dictionary].date = ["$(today())"]
        add_audit_message!(proto_dict, "(DDLm conversion) Specified Set categories $common_set_cats")
    end
end

"""
    align_aliases(proto_dict, reference_dict)

Make sure that all aliased data names appear only once. If reference_dict
contains an alias, remove the same definition from proto_dict
"""
align_aliases!(proto_dict, reference_dict) = begin

    # find aliases in proto_dict
    remember = []

    for one_alias in reference_dict[:alias].definition_id
        locs = findall(x -> x == one_alias, proto_dict[:alias].definition_id)
        if length(locs) == 0 continue end

        # Prefer the data name that comes from reference_dict

        for h in proto_dict[:alias].master_id[locs]
            if !(h in reference_dict[:alias].master_id) #identical
                @debug "Deleting definition for $h"
                delete!(proto_dict, h)
                push!(remember, h)
            end
        end
    end

    @debug "Removed $(length(remember)) definitions" remember

    # And remove any categories where the keys belong to a different category
    # due to deprecation. See diffrn_frame_data/diffrn_data_frame in imgCIF.

    bad_cats = []
    for one_row in eachrow(proto_dict[:category_key])
        fc = find_category(proto_dict, one_row.name)
        if fc != one_row.master_id && !isnothing(fc)
            @debug "Found keys outside their category" one_row find_category(proto_dict, one_row.name)
            push!(bad_cats, one_row.master_id)
        end
        if isnothing(fc)

            # This may happen if the data name has been deleted in alias removal above. The
            # name will be defined in the imported dictionary.
            @warn "$(one_row.name) doesn't belong to any category??"
        end
    end

    for bc in unique!(bad_cats)
        if length(get_names_in_cat(proto_dict, bc)) == 0
            delete!(proto_dict, bc)
        end
    end
    @debug "Removed $bad_cats from dictionary"
end

"""
     provide_missing_keys(proto_dict,parent,cats,descr_text)

    Add keys pointing to `parent` dataname for all categories in `cats` found in `proto_dict`.
    If parent is of form `_<parent_cat>.<object>`, the keys will be named 
    `_<cat>.<parent_cat>_<object>` e.g. parent = "_diffrn.id" => "_child.diffrn_id".
    Text in `descr_text` is used for the data name description. 
"""
provide_missing_keys(proto_dict,parent,cats,descr_text) = begin
    cat,obj = split(parent,".")
    cat = cat[2:end]  # drop leading underscore
    for child_cat in cats
        new_def = Dict{Symbol,DataFrame}()
        new_obj = cat*"_"*obj
        new_dn = "_"*child_cat*"."*new_obj
        if haskey(proto_dict,new_dn)
            @info "$new_dn already in dictionary, skipping"
            continue
        end
        new_def[:name] = DataFrame(:object_id=>[new_obj],
                                   :category_id=>[child_cat],
                                   :linked_item_id=>[parent]
                                   )
        new_def[:type] = DataFrame(:source=>["Related"],
                                   :purpose=>["Link"],
                                   :container=>["Single"],
                                   :contents=>["Word"]
                                   )
        new_def[:definition] = DataFrame(:id=>[new_dn],
                                         :update=>["$(today())"])
        new_def[:description] = DataFrame(:text=>[descr_text])
        add_definition!(proto_dict,new_def)
        
        # Now deal with the category definition itself

        add_key!(proto_dict,new_dn)
    end 
end

expand_keys(d::DDLm_Dictionary,keyname,text) = begin
    cat,obj = split(keyname,".")
    cat = cat[2:end]
    all_cats = get_categories(d, head = false)
    filter!(x->match(Regex("$(cat)_"),x)!=nothing,all_cats)
    @info "Adding keys to these cats:" all_cats
    descr = text*" Values of this item are drawn from values of $keyname."
    provide_missing_keys(d,keyname,all_cats,descr)
end
"""
    Remove any definitions that are repeated as aliases. Remove aliases if
    they match the definition.
"""
remove_aliases!(d::DDLm_Dictionary) = begin

    # First remove aliases to themselves
    underlying = parent(d.block[:alias])
    before = size(underlying, 1)
    @debug "Before dropping self-aliases: $before"
    filter!( x -> x.definition_id != x.master_id, underlying)
    after = size(underlying, 1)
    @debug "After dropping self-aliases: $after"
    d.block[:alias] = groupby(underlying, "master_id")
    aliased = d[:alias][!,:definition_id]
    defed = d[:definition][!,:id]
    doubled_up = intersect(lowercase.(aliased), lowercase.(defed))
    @debug "Aliases as definitions: $doubled_up"
    for du in doubled_up
        if :definition_id in propertynames(d[du][:alias]) && du in d[du][:alias][!,:definition_id]
            @warn "Definition aliased to itself: $du; removing alias only"
            
            continue
        end
        delete!(d, du)
    end

    if before != after || length(doubled_up) > 0   #leave audit message
        add_audit_message!(d, "(DDLm conversion) Removed redundant aliases and definitions for aliased data names $doubled_up")
    end
end

"""
    Use semantic versioning. Add '.0' if version number too short, insert
    prefix if too long.
"""
proper_versions!(d::DDLm_Dictionary) = begin
    version_list = d[:dictionary_audit][!,:version]
    new_versions = map(version_list) do one_v
        in_bits = split(one_v, '.')

        if length(in_bits) == 3
            one_v
        elseif length(in_bits) == 2
            @debug "Appending 0"
            push!(in_bits, "0")
            join(in_bits, ".")
        elseif length(in_bits) > 3
            @debug "Appending -dev"
            new_v = join(in_bits[1:3], ".")
            new_v * "-dev" * join(in_bits[4:end],'.')
        end
    end
    d[:dictionary_audit][!,:version] = new_versions
end

"""
     Remove any attributes that are purely for DDL2 preservation
"""
drop_ddl2!(d::DDLm_Dictionary) = begin

    # Remove only categories starting with "ddl2"
    
    for c in keys(d.block)
        if String(c)[1:4] == "ddl2"
            @debug "Removing category $c"
            p = parent(d.block[c]) #unused
            delete!(d.block, c)
        end
    end

    add_audit_message!(d, "(DDLm conversion) Removed DDL2-only categories")
end

"""
    Add `to_be_imported` to the list of imported dictionaries of `d`
"""
insert_import(d::DDLm_Dictionary, to_be_imported; short = false) = begin
    other_head = find_head_category(to_be_imported)
    other_global = get_dic_name(to_be_imported)
    other_uri = to_be_imported[other_global][:dictionary].uri[]
    if short
        other_uri = basename(URI(other_uri).path)
    end
    head = find_head_category(d)
    import_spec = Dict("save"=>other_head,"file"=>other_uri,"mode"=>"Full","dupl"=>"Ignore")
    current_import = Dict{String,String}[]
    if haskey(d[head],:import)
        current_import = d[head][:import].get[]
    end
    if ismissing(current_import)
        current_import = Dict{String,String}[]
    end
    push!(current_import,import_spec)
    update_dict!(d,head,"_import.get",current_import)
end

"""
    Sort results of splitting version string with at least three components.
"""
version_sort(v1::String, v2::String) = begin
    mmp1 = split(v1,'.')
    mmp2 = split(v2,'.')

    maj1 = parse(Int, mmp1[1])
    maj2 = parse(Int, mmp2[1])

    # Major compare

    if maj1 < maj2
        return true
    elseif maj2 < maj1
        return false
    end

    # Minor compare

    min1 = parse(Int, mmp1[2])
    min2 = parse(Int, mmp2[2])

    if min1 < min2
        return true
    elseif min2 < min1
        return false
    end

    # Patch compare

    patch1 = parse(Int, match(r"[0-9]+", mmp1[3]).match)
    patch2 = parse(Int, match(r"[0-9]+", mmp2[3]).match)
    if patch1 < patch2
        return true
    elseif patch2 < patch1
        return false
    end

    # trailing stuff compare
    return mmp1[3] < mmp2[3]
    
end

translate(from_dict, from_namespace; set_source = nothing, add_import=false, text="", dic_title = nothing, new_key = nothing, short = false, strict = false, postprocess = false) = begin

    if !postprocess
        to_namespace = from_namespace == "ddlm" ? "ddl2" : "ddlm"

        category_holder,as_dic = prepare_data(from_dict,to_namespace)
 
        force_translate(category_holder,to_namespace)
    
        # And now construct a dictionary from a datasource

        dividers = ["_definition.id"]
        other_dict = typeof(category_holder.dict[to_namespace])

        println("#== Creating dictionary $other_dict ==#")
        output = other_dict(select_namespace(category_holder,to_namespace), category_holder.dict[to_namespace], dividers)

    else
        to_namespace = from_namespace
        output = if to_namespace == "ddlm"
            DDLm_Dictionary(from_dict, ignore_imports = :Full)
        else
            DDL2_Dictionary(from_dict)
        end
    end
    
    # Rename Title and Head category as per DDLm style

    if !isnothing(dic_title)
        rename_dictionary!(output, dic_title)
    end
    
    # Adjust set categories if requested

    if set_source != nothing && to_namespace == "ddlm"
        core_dic = DDLm_Dictionary(set_source)

        println("#== Aligning Set Categories ==#")
        align_set_cats(output,core_dic)
    end

    # Add key data names

    if new_key != nothing

        println("#== Expanding $new_key ==#")
        expand_keys(output,new_key,text)
    end

    # Remove aliases

    if strict && to_namespace == "ddlm"
        
        println("#== Removing aliased definitions ==#")
        remove_aliases!(output)
        if set_source != nothing
            align_aliases!(output, core_dic)
        end

        # Fix version numbers

        println("#== Fixing version numbers ==#")
        proper_versions!(output)
        
        # Sort version numbers (DDLm style)

        println("#== Changing version number order ==#")
        sort!(output[:dictionary_audit], :version, lt = version_sort)
        
        # Remove any non-DDLm attributes

        println("#== Removing non-DDLm attributes ==#")
        drop_ddl2!(output)

    end

    # Add any imports

    if add_import && set_source != nothing

        println("#== Inserting import statement ==#")
        insert_import(output,core_dic, short = short)
    end

    return output, to_namespace
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "-c", "--core"
        help = "Align Set categories with this dictionary. See also option -i"
        nargs = 1
        "-i", "--import"
        help = "The output dictionary should import the dictionary specified by the '-c' option"
        nargs = 0
        "--short"
        help = "Specify import (-i option) in output file using filename only"
        nargs = 0
        "--strict"
        help = "Output strictly conforming DDLm dictionary. Cannot be used to translate back to DDL2"
        nargs = 0
        "-t", "--title"
        help = "Title for the dictionary. Do not use if the output should be round-tripped."
        nargs = 1
        "-k", "--keys"
        help = "The argument is a data name of form <cat>.<obj>. All categories starting with <cat> will have an additional key data name added referring to this data name"
        nargs = 1
        "-p", "--postprocess"
        help = "Only apply post-transformation changes to the supplied file."
        nargs = 0
        "--text"
        help = "Text to be inserted in definition of new keys (see -k argument)"
        nargs = 1
        default = [""]
        "-o", "--output"
        help = "Name of output dictionary, otherwise input with 'to_<lang>.dic' appended"
        "dictionary"
        help = "Name of dictionary to convert"
        required = true
        "source_lang"
        help = "Language of source dictionary: either ddl2 or ddlm"
        required = true
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline("Convert between ddl2 and ddlm dictionaries")
    source_dic = parsed_args["dictionary"]
    source_lang = parsed_args["source_lang"]
    core = parsed_args["core"]
    postprocess = parsed_args["postprocess"]
    @info "Arguments" parsed_args
    result, to_namespace = translate(source_dic,source_lang,
                                     set_source= parsed_args["core"] == [] ? nothing : parsed_args["core"][],
                                     dic_title = parsed_args["title"] == [] ? nothing : parsed_args["title"][],
                                     add_import = parsed_args["import"],
                                     short = parsed_args["short"],
                                     strict = parsed_args["strict"],
                                     postprocess = postprocess,
                                     text = parsed_args["text"][])

    # And output this monster

    outname = parsed_args["output"]
    if postprocess
        fname = outname == nothing ? source_dic * "_postprocess" : outname
    else
        fname = outname == nothing ? source_dic*"to_$to_namespace.dic" : outname
    end
    outfile = open(fname,"w")
    println("#=== We have a dictionary ===#")
    @debug "Before output" result
    Base.show(outfile,MIME("text/cif"), result)
    close(outfile)

end
