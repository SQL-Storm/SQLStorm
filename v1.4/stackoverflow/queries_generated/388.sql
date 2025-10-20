-- {"query": "388.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25090} 
WITH YearPosts AS (
  SELECT p.Id, p.OwnerUserId, p.Score, p.LastActivityDate, p.Tags, p.CreationDate, p.PostTypeId
  FROM Posts p
  WHERE p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '365 days'
),
ActiveBase AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS YearPostCount,
    COALESCE(SUM(p.Score), 0) AS YearScoreSum,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN YearPosts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(p.Id) > 0
),
ActiveWithRank AS (
  SELECT a.UserId, a.DisplayName, a.Reputation, a.YearPostCount, a.YearScoreSum, a.LastActivityDate,
         ROW_NUMBER() OVER (ORDER BY a.YearScoreSum DESC, a.YearPostCount DESC) AS rn
  FROM ActiveBase a
  WHERE a.YearScoreSum > 0 OR a.YearPostCount > 0
),
ActiveDetailed AS (
  SELECT
    awr.UserId,
    awr.DisplayName,
    awr.Reputation,
    awr.YearPostCount,
    awr.YearScoreSum,
    awr.LastActivityDate,
    (
      SELECT COALESCE(STRING_AGG(DISTINCT tg.TagName, ','), '')
      FROM YearPosts yp
      CROSS JOIN LATERAL UNNEST(
        CASE
          WHEN yp.Tags IS NULL OR length(yp.Tags) <= 2 THEN ARRAY[]::text[]
          ELSE string_to_array(substring(yp.Tags from 2 for length(yp.Tags) - 2), '><')
        END
      ) AS tg(TagName)
      WHERE yp.OwnerUserId = awr.UserId
    ) AS DistinctTags,
    (
      SELECT po.Title
      FROM Posts po
      WHERE po.OwnerUserId = awr.UserId
      ORDER BY po.LastEditDate DESC
      LIMIT 1
    ) AS LastEditedPostTitle,
    'Active' AS Category,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = awr.UserId AND b.Class = 1
    ) AS GoldBadges
  FROM ActiveWithRank awr
  WHERE awr.rn <= 100
),
Emerging AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS YearPostCount,
    0 AS YearScoreSum,
    NULL AS LastActivityDate,
    NULL AS DistinctTags,
    NULL AS LastEditedPostTitle,
    'Emerging' AS Category,
    0 AS GoldBadges
  FROM Users u
  WHERE NOT EXISTS (
        SELECT 1
        FROM YearPosts yp
        WHERE yp.OwnerUserId = u.Id
  )
  ORDER BY u.Reputation DESC
  LIMIT 100
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  YearPostCount,
  YearScoreSum,
  LastActivityDate,
  DistinctTags,
  LastEditedPostTitle,
  Category,
  GoldBadges
FROM ActiveDetailed
UNION ALL
SELECT
  UserId,
  DisplayName,
  Reputation,
  YearPostCount,
  YearScoreSum,
  LastActivityDate,
  DistinctTags,
  LastEditedPostTitle,
  Category,
  GoldBadges
FROM Emerging
ORDER BY Category, YearScoreSum DESC NULLS LAST
LIMIT 200;