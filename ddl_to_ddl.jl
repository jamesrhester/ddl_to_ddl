# A program to translate the imgCIF dictionary to DDLm

using CrystalInfoFramework
using CrystalInfoFramework.DataContainer
using DrelTools
using ArgParse
using DataFrames
using Dates

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
    return TypedDataSource(as_data(ddl2dic),ddl2_trans_dic),ddl2dic
end    

load_dictionary_as_data(::Type{DDLm_Dictionary}, filename) = begin
    ddlmdic = DDLm_Dictionary(filename)
    return TypedDataSource(as_data(ddlmdic),ddlm_trans_dic),ddlmdic
end    

force_translate(category_holder,to_namespace) = begin
    trans_dic = get_dictionary(category_holder,to_namespace)
    all_cats = get_categories(trans_dic)
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
    dic_datasource,as_dic = load_dictionary_as_data(dictype,input_dict)
    category_holder = DynamicDDLmRC(dic_datasource,att_ref)
    # add our target dictionary as well
    category_holder.dict[to_namespace] = other_ref 
    category_holder.value_cache[to_namespace] = Dict{String,Any}()
    category_holder.cat_cache[to_namespace] = Dict{String,CifCategory}()
    return category_holder,as_dic
end

"""
    align_set_cats(proto_dict,reference_dict)

Make all categories common to `proto_dict` and `reference_dict` 
match Set/Loop by changing `proto_dict` accordingly.

"""
align_set_cats(proto_dict::DDLm_Dictionary,reference_dict::DDLm_Dictionary) = begin
    pd_cats = get_categories(proto_dict)
    common_set_cats = intersect(pd_cats,get_set_categories(reference_dict))
    @debug "Common set cats: $common_set_cats"
    for cs in common_set_cats
        update_dict!(proto_dict,cs,"_definition.class","Set")
        update_dict!(proto_dict,cs,"_definition.update","$(today())")
    end
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
    all_cats = get_categories(d)
    filter!(x->match(Regex("$(cat)_"),x)!=nothing,all_cats)
    @info "Adding keys to these cats:" all_cats
    descr = text*" Values of this item are drawn from values of $keyname."
    provide_missing_keys(d,keyname,all_cats,descr)
end

"""
    Add `to_be_imported` to the list of imported dictionaries of `d`
"""
insert_import(d::DDLm_Dictionary,to_be_imported) = begin
    other_head = find_head_category(to_be_imported)
    other_global = get_dic_name(to_be_imported)
    other_uri = to_be_imported[other_global][:dictionary].uri[]
    head = find_head_category(d)
    import_spec = Dict("save"=>other_head,"file"=>other_uri,"mode"=>"Full")
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

translate(from_dict,from_namespace; outname=nothing,set_source = nothing, new_key=nothing, add_import=false, text="") = begin
    to_namespace = from_namespace == "ddlm" ? "ddl2" : "ddlm"
    category_holder,as_dic = prepare_data(from_dict,to_namespace)
    force_translate(category_holder,to_namespace)
    
    # And now construct a dictionary from a datasource

    dividers = ["_definition.id"]
    other_dict = typeof(category_holder.dict[to_namespace])
    output = other_dict(select_namespace(category_holder,to_namespace),category_holder.dict[to_namespace],dividers)
    
    # Adjust set categories if requested

    if set_source != nothing && to_namespace == "ddlm"
        core_dic = DDLm_Dictionary(set_source)
        align_set_cats(output,core_dic)
    end

    # Add key data names

    if new_key != nothing
        expand_keys(output,new_key,text)
    end

    # Add any imports

    if add_import && set_source != nothing
        insert_import(output,core_dic)
    end

    # And output this monster
    
    fname = outname == nothing ? from_dict*"to_$to_namespace.dic" : outname
    outfile = open(fname,"w")
    println("#=== We have a dictionary ===#")
    println("$(output.block)")
    Base.show(outfile,MIME("text/cif"),output)
    close(outfile)
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
        "-k", "--keys"
        help = "The argument is a data name of form <cat>.<obj>. All categories starting with <cat> will have an additional key data name added referring to this data name"
        nargs = 1
        "-t", "--text"
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
    @info "Arguments" parsed_args
    translate(source_dic,source_lang,outname = parsed_args["output"],
              set_source= parsed_args["core"] == [] ? nothing : parsed_args["core"][],
              new_key = parsed_args["keys"] == [] ? nothing : parsed_args["keys"][],
              add_import = parsed_args["import"],
              text = parsed_args["text"][])
end
