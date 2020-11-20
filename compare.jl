# Compare two dictionaries, producing a report
using CrystalInfoFramework,DataFrames

const ddl2_ref_dic = DDL2_Dictionary("ddl2_with_methods.dic")
#
# The DDL2 categories that we care about
#
const ddl2_test_categories = [:item_range,:item_default,:item,
                              :category,:category_key,
                              :dictionary_history,
                              :item_type,
                              :item_linked,
                              :item_examples,
                              :item_enumeration,
                              :item_description,
                              :item_aliases,
                              :dictionary,
                              :category_examples,
                              :category_description
                              ]
#
# Find definitions that are present in one and not the other
#
find_missing_defs(dica,dicb) = begin
    a = lowercase.(keys(dica))
    b = lowercase.(keys(dicb))
    differenta = setdiff(a,b)
    differentb = setdiff(b,a)
    return differenta,differentb
end

#
# Find attributes in the definition in dica from cat that are missing or
# different in dicb
#
report_missing_attrs(defa,defb,name,cat) = begin
    if haskey(defa,cat)
        adef = defa[cat]
        if haskey(defb,cat)
            bdef = defb[cat]
            if nrow(adef) != nrow(bdef)
                println("$cat has different number of rows for $name")
            end
            # check columns
            anames = names(adef)
            bnames = names(bdef)
            do_not_have = setdiff(anames,bnames,["master_id","__object_id","__blockname"])
            if length(do_not_have) > 0
                println("$name: missing $do_not_have")
            end
            common = intersect(anames,bnames)
            # println("$cat")
            # loop and check values
            catkeys = get_keys_for_cat(ddl2_ref_dic,cat)
            catobjs = Symbol.([find_object(ddl2_ref_dic,x) for x in catkeys])
            nonmatch = check_matching_rows(adef,bdef,catobjs)
            if nrow(nonmatch) > 0
                println("The following rows do not have matching keys for $cat:")
                println("$nonmatch")
            end
            # now check all
            nonmatch = check_matching_rows(adef,bdef,common)
            if nrow(nonmatch) > 0
                println("The following rows have at least one mismatched value for $cat:")
                println("$nonmatch")
            end
        else
            println("$cat is missing from $name in second dictionary")
            println("First dictionary has $adef")
        end
    end
end

check_matching_rows(dfa,dfb,keylist) = begin
    #println("Checking rows $keylist")
    test = antijoin(dfa,dfb,on=keylist,validate=(false,true))
    return test
end

report_diffs(source_lang,dics) = begin
    if source_lang == "ddl2"
        dica,dicb = DDL2_Dictionary.(dics)
    else
        dica,dicb = DDLm_Dictionary.(dics)
    end
    difa,_ = find_missing_defs(dica,dicb)
    println("Warning: missing definitions for $difa")
    for one_def in sort(collect(keys(dica)))
        println("\n#=== $one_def ===#\n")
        if one_def in difa
            println("$one_def missing from second dictionary")
            continue
        end
        defa = dica[one_def]
        defb = dicb[one_def]
        for one_cat in ddl2_test_categories
            report_missing_attrs(defa,defb,one_def,one_cat)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 3
        println("""
Usage: julia $(basename(PROGRAM_FILE)) <lang> <dictionary1> <dictionary2> where <lang> is either "ddl2" or "ddlm" """)
        exit()
    end
    source_lang = ARGS[1]
    dics = (ARGS[2],ARGS[3])
    report_diffs(source_lang,dics)
end
