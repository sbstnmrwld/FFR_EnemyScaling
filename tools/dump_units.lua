-- MogHub dev_eval script (Debug = 1, copy to Mods/MogHub/dev_eval.lua while the game runs): writes every row of
-- DT_UnitParameter as tab-separated text to dev_eval_out.txt, the input of curves.pl:
--   perl tools/curves.pl dev_eval_out.txt
local F = { "ID", "Category", "Level", "IsBoss", "MaxHitPoint", "MaxBreakPoint", "Attack", "Defence", "Intelligence",
            "Mind", "Agility", "Divine", "Experience", "Money" }
kit.tables.rows("UNIT_PARAMETER", function(row, name)
    local p = {}
    for _, f in ipairs(F) do p[#p + 1] = tostring(row[f]) end
    local ok, n = pcall(function() return row.Name:ToString() end)
    p[#p + 1] = ok and n or "?"
    p[#p + 1] = tostring(name)
    out(table.concat(p, "\t"))
end)
