-- {"query": "5918.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 418} 
WITH TagActivity AS (
  SELECT
    t.TagName,
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON true
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    MAX(LastActivityDate) AS LastActive
  FROM TagActivity
  GROUP BY TagName
  HAVING COUNT(*) > 50
),
Correlation AS (
  SELECT
    tt.TagName,
    tt.PostCount,
    tt.AvgScore,
    tt.LastActive,
    (SELECT AVG(Score) FROM Posts WHERE Tags LIKE '%' || tt.TagName || '%' AND PostTypeId = 1) AS GlobalAvgScore
  FROM TopTags tt
),
CrossJoinStats AS (
  SELECT
    c.TagName,
    c.PostCount,
    c.AvgScore,
    c.LastActive,
    c.GlobalAvgScore,
    (c.AvgScore - c.GlobalAvgScore) AS ScoreDelta,
    PERCENT_RANK() OVER (ORDER BY (c.AvgScore - c.GlobalAvgScore)) AS PRank
  FROM Correlation c
)
SELECT
  c.TagName,
  c.PostCount,
  c.AvgScore,
  c.LastActive,
  c.GlobalAvgScore,
  c.ScoreDelta,
  c.PRank
FROM CrossJoinStats c
ORDER BY c.PRank, c.PostCount DESC
LIMIT 100;