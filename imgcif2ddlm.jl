# A program to translate the imgCIF dictionary to DDLm

using CrystalInfoFramework
using DataContainer
using CIF_dREL

const ddl2_atts = DDL2_Dictionary(joinpath(@__DIR__,"ddl_core_2.1.3.dic"))
const ddlm_trans_dic = DDLm_Dictionary(joinpath(@__DIR__,"ddlm_from_ddl2.dic"))

"""
Load a dictionary as a data source.  We return the dictionary interpretation as well
to make use of high-level information
"""
load_dictionary_as_data(filename) = begin
    #c = MultiDataSource(NativeCif(filename))
    #TypedDataSource(c,ddl2_atts),DDL2_Dictionary(filename)
    ddl2dic = DDL2_Dictionary(filename)
    return TypedDataSource(as_data(ddl2dic),ddl2_atts),ddl2dic
end    

force_translate(category_holder,as_ddl2_dic) = begin
    all_cats = get_categories(ddlm_trans_dic)
    for one_cat in all_cats
        println("# Attempting to translate $one_cat\n")
        try
            va = get_category(category_holder,one_cat,"ddlm")
        catch e
            if e isa KeyError continue end
            rethrow()
        end
        println("# Now doing individual items\n")
        all_items = get_names_in_cat(ddlm_trans_dic,one_cat)
        for one_item in all_items
            print("# Translating $one_item...")
            try
                va = category_holder[one_item,"ddlm"]
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

prepare_data(written_in_ddl2) = begin
    dic_datasource,as_ddl2_dic = load_dictionary_as_data(written_in_ddl2)
    category_holder = DynamicDDLmRC(dic_datasource,ddl2_atts)
    # add our DDLm dictionary as well
    target_nspace = get_dic_namespace(ddlm_trans_dic)
    category_holder.dict[target_nspace] = ddlm_trans_dic
    category_holder.value_cache[target_nspace] = Dict{String,Any}()
    return category_holder,as_ddl2_dic
end

translate(written_in_ddl2) = begin
    category_holder,as_ddl2_dic = prepare_data(written_in_ddl2)
    force_translate(category_holder,as_ddl2_dic)
    # And now construct a dictionary from a datasource
    dividers = ["_definition.id"]
    output = DDLm_Dictionary(select_namespace(category_holder,"ddlm"),ddlm_trans_dic,dividers)
    outfile = open("trans_test.dic","w")
    println("#=== We have a dictionary ===#")
    println("$(output.block)")
    Base.show(outfile,MIME("text/cif"),output)
    close(outfile)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia $(basename(PROGRAM_FILE)) file_to_translate")
        exit()
    end
    source_dic = ARGS[1]
    translate(source_dic)
end
