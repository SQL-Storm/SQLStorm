WITH RecursiveDefense AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        uth_cycle.ID AS recursive_path,
        1 AS step,
        ARRAY[p.Id] AS cycle_detect
    FROM Posts p
    LEFT JOIN (
        SELECT die_construct.construct AS ID
        FROM (SELECT 1 AS construct) die_construct
        CROSS JOIN (SELECT 1 AS used) used_alias
    ) uth_cycle ON TRUE
)
SELECT
    rd.PostId,
    rd.Title,
    rd.OwnerUserId,
    rd.recursive_path,
    rd.step,
    rd.cycle_detect
FROM RecursiveDefense rd
GROUP BY
    rd.PostId,
    rd.Title,
    rd.OwnerUserId,
    rd.recursive_path,
    rd.step,
    rd.cycle_detect;