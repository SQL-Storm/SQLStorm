-- {"query": "325.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22771} 
WITH Q1 AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    MAX(p.ViewCount) AS MaxViews,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS MaxQuestionViews,
    (
      (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) +
      (SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) * 4) +
      (COUNT(p.Id) * 0.5) +
      (MAX(p.ViewCount) * 0.001) +
      (u.Reputation * 0.0005)
    ) AS CompositeScore,
    (
      SELECT s.TagName
      FROM (
        SELECT t.TagName, COUNT(*) AS c
        FROM Posts pp
        CROSS JOIN LATERAL unnest(string_to_array(substring(pp.Tags, 2, length(pp.Tags) - 2), '><')) AS t(TagName)
        WHERE pp.OwnerUserId = u.Id
        GROUP BY t.TagName
        ORDER BY c DESC
        LIMIT 1
      ) AS s
    ) AS TopTagName
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Q2 AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS PostCount,
    NULL AS AvgQuestionScore,
    0 AS UpVotes,
    0 AS DownVotes,
    0 AS BadgeCount,
    0 AS GoldBadges,
    0 AS MaxViews,
    0 AS MaxQuestionViews,
    0 AS CompositeScore,
    (
      SELECT s.TagName
      FROM (
        SELECT t.TagName, COUNT(*) AS c
        FROM Posts pp
        CROSS JOIN LATERAL unnest(string_to_array(substring(pp.Tags, 2, length(pp.Tags) - 2), '><')) AS t(TagName)
        WHERE pp.OwnerUserId = u.Id
        GROUP BY t.TagName
        ORDER BY c DESC
        LIMIT 1
      ) AS s
    ) AS TopTagName
  FROM Users u
)
SELECT *
FROM (
  SELECT * FROM Q1
  UNION ALL
  SELECT * FROM Q2
) AS Benchmark
ORDER BY CompositeScore DESC
LIMIT 200;