# A program to translate the imgCIF dictionary to DDLm

using CrystalInfoFramework
using DataContainer
using CIF_dREL

#
# There are plain versions to avoid a cycle of derivations pinballing between ddl2
# and ddlm methods
#
const ddl2_trans_dic = DDL2_Dictionary(joinpath(@__DIR__,"ddl2_with_methods.dic"))
const ddlm_trans_dic = DDLm_Dictionary(joinpath(@__DIR__,"ddlm_from_ddl2.dic"))
const ddl2_plain_dic = DDL2_Dictionary(joinpath(@__DIR__,"ddl_core_2.1.3.dic"))
const ddlm_plain_dic = DDLm_Dictionary(joinpath(@__DIR__,"ddl.dic"))

"""
Load a dictionary as a data source.  We return the dictionary interpretation as well
to make use of high-level information
"""
load_dictionary_as_data(::Type{DDL2_Dictionary}, filename) = begin
    #c = MultiDataSource(NativeCif(filename))
    #TypedDataSource(c,ddl2_atts),DDL2_Dictionary(filename)
    ddl2dic = DDL2_Dictionary(filename)
    return TypedDataSource(as_data(ddl2dic),ddl2_trans_dic),ddl2dic
end    

load_dictionary_as_data(::Type{DDLm_Dictionary}, filename) = begin
    #c = MultiDataSource(NativeCif(filename))
    #TypedDataSource(c,ddl2_atts),DDL2_Dictionary(filename)
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
        att_ref = ddlm_plain_dic
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

translate(from_dict,from_namespace) = begin
    to_namespace = from_namespace == "ddlm" ? "ddl2" : "ddlm"
    category_holder,as_dic = prepare_data(from_dict,to_namespace)
    force_translate(category_holder,to_namespace)
    # And now construct a dictionary from a datasource
    dividers = ["_definition.id"]
    other_dict = typeof(category_holder.dict[to_namespace])
    output = other_dict(select_namespace(category_holder,to_namespace),category_holder.dict[to_namespace],dividers)
    outfile = open(from_dict*"to_$to_namespace.dic","w")
    println("#=== We have a dictionary ===#")
    println("$(output.block)")
    Base.show(outfile,MIME("text/cif"),output)
    close(outfile)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 2
        println("""
Usage: julia $(basename(PROGRAM_FILE)) <dictionary> <source_lang> where <source_lang> is either "ddl2" or "ddlm" """)
        exit()
    end
    source_dic = ARGS[1]
    source_lang = ARGS[2]
    translate(source_dic,source_lang)
end
