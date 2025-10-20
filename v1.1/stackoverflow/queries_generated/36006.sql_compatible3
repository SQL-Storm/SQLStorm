SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
  MAX(p.CreationDate) AS LatestPostDate,
  STRING_AGG(DISTINCT t.tag, ',') AS TagsUsed
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT value AS tag
    FROM (
      SELECT TRIM(BOTH '"' FROM v) AS value
      FROM (
        SELECT
          CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
            ELSE
              -- convert > &lt; style to comma-separated tags inside quotes: <tag1><tag2> -> "tag1","tag2"
              -- produce a JSON-like array string
              ('"' ||
               REPLACE(
                 REPLACE(
                   REPLACE(
                     REPLACE(
                       REPLACE(p.Tags, '&lt;', '<'),
                       '&gt;', '>'
                     ),
                     '><', '","'
                   ),
                   '<', ''
                 ),
                 '>', ''
               )
               || '"'
              )
          END AS json_like_array
      ) s,
      LATERAL (
        -- split the json_like_array on comma into rows; handle NULLs
        SELECT regexp_split_to_table(s.json_like_array, ',') AS v
      ) t2
      WHERE s.json_like_array IS NOT NULL
    ) sub
  ) AS t ON TRUE
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  TotalViews DESC, AvgPostScore DESC
LIMIT 100;