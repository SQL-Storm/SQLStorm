-- {"query": "304.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17832} 
WITH
TagPairs AS (
  SELECT p.OwnerUserId AS UserId, t.TagName
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
),
TagCounts AS (
  SELECT UserId, TagName, COUNT(*) AS TagPostCount
  FROM TagPairs
  GROUP BY UserId, TagName
),
TopTagPerUser AS (
  SELECT UserId, TagName
  FROM (
    SELECT UserId, TagName, ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC) AS rn
    FROM TagCounts
  ) AS t
  WHERE rn = 1
),
UserDailyStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(p.Id) AS PostCountLastYear,
         AVG(p.Score) AS AvgScoreLastYear,
         MAX(p.CreationDate) AS LastPostDateYear,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId IN (SELECT Id FROM Posts p2 WHERE p2.OwnerUserId = u.Id)) AS TotalCommentCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= now() - interval '365 days'
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  du.UserId,
  du.DisplayName,
  du.Reputation,
  COALESCE(du.PostCountLastYear, 0) AS PostCountLastYear,
  COALESCE(du.AvgScoreLastYear, 0) AS AvgScoreLastYear,
  du.LastPostDateYear,
  COALESCE(t.TagName, 'NoTag') AS TopTagName,
  du.TotalCommentCount,
  ROW_NUMBER() OVER (ORDER BY du.LastPostDateYear DESC NULLS LAST, du.AvgScoreLastYear DESC, du.PostCountLastYear DESC) AS UserRank,
  'https://stackoverflow.com/users/' || du.UserId AS ProfileUrl
FROM UserDailyStats du
LEFT JOIN TopTagPerUser t ON t.UserId = du.UserId
ORDER BY UserRank
LIMIT 100;