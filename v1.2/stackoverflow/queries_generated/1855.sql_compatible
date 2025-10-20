WITH RecursiveTagEntropy AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn,
    LENGTH(t.TagName) AS TagLength,
    CASE 
      WHEN POSITION('a' IN LOWER(t.TagName)) > 0 THEN 1 ELSE 0
    END AS HasChar_a,
    CAST(0.0 AS DOUBLE PRECISION) AS WeightedHet
  FROM
    tags t
)
SELECT
  rte.Id,
  rte.TagName,
  rte.Count,
  rte.rn,
  rte.TagLength,
  rte.HasChar_a,
  rte.WeightedHet
FROM
  RecursiveTagEntropy rte
GROUP BY
  rte.Id,
  rte.TagName,
  rte.Count,
  rte.rn,
  rte.TagLength,
  rte.HasChar_a,
  rte.WeightedHet;