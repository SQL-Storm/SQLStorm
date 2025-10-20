WITH TagRanks AS (
  SELECT
    t.Id,
    t.TagName,
    row_number() OVER (PARTITION BY substr(t.TagName, 1, 100) ORDER BY t.Id) AS rn
  FROM tags t
)
SELECT
  tr.Id,
  tr.TagName,
  tr.rn
FROM TagRanks tr
ORDER BY tr.Id;