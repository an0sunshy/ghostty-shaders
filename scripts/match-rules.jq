# match-rules.jq — the scene-matching rule engine.
#
# Input  (stdin):  the merged facts object, e.g.
#                  {"weather":"snow","phase":"night","season":"winter","temp_c":-3}
# Args:    --argjson rules  <collections/poems.rules.json>
#          --argjson index  <collections/poems.index.json>
# Output:  one "<scene>\t<score>" line per NON-vetoed scene (raw scores; the
#          caller applies recency + softmax sampling).
#
# A condition matches by type: object => operator ({"<=":n} etc.), array =>
# membership, scalar => equality. A condition on an absent fact never matches,
# so partial/offline facts simply fire fewer rules. A rule fires when ALL of
# its `when` conditions match; a fired rule contributes `boost` (tag=>weight)
# and `veto` (tags that disqualify any scene carrying them).

def match_cond($facts; $key; $m):
  ($facts[$key]) as $v
  | if $v == null then false
    elif ($m | type) == "object" then
      ($m | to_entries[0]) as $e
      | ($e.value) as $n
      | if   $e.key == "<=" then $v <= $n
        elif $e.key == ">=" then $v >= $n
        elif $e.key == "<"  then $v <  $n
        elif $e.key == ">"  then $v >  $n
        elif $e.key == "ne" then $v != $n
        else false end
    elif ($m | type) == "array" then ($m | index($v)) != null
    else $v == $m
    end;

def rule_fires($facts; $when):
  [ $when | to_entries[] | match_cond($facts; .key; .value) ] | all;

. as $facts
| [ ($rules.rules // [])[] | select(rule_fires($facts; (.when // {}))) ] as $fired
| ( reduce $fired[] as $r ({};
      reduce (($r.boost // {}) | to_entries[]) as $b
        (.; .[$b.key] = ((.[$b.key] // 0) + $b.value)) ) ) as $tagw
| ( [ $fired[] | (.veto // [])[] ] | unique ) as $vetoed
| ($index.scenes // {}) | to_entries[]
| .key as $scene
| (.value.tags // []) as $tags
| if ($tags | map(. as $t | ($vetoed | index($t)) != null) | any)
  then empty
  else "\($scene)\t\([ $tags[] | ($tagw[.] // 0) ] | add // 0)"
  end
