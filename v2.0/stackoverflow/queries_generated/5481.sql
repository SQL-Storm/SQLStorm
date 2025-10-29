-- {"query": "5481.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 618} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.AccountId
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
),
tag_pop AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  GROUP BY t.TagName
),
complex_calc AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    (u.Reputation * 1.0 / NULLIF(u.AccountId,0)) AS ReputationIndex,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = u.Id) AS AvgPostScoreByUser,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS UserComments
  FROM Users u
)
SELECT
  tuid.UserId,
  tu.DisplayName AS UserName,
  tu.Reputation,
  tu.PostCount,
  ra.PostId,
  ra.Title AS PostTitle,
  ra.Tags,
  ra.LastActivityDate,
  tpu.TagName,
  tpu.TagCount,
  tpu.AvgPostScore,
  cc.ReputationIndex,
  cc.AvgPostScoreByUser,
  cc.UserComments
FROM top_users tu
LEFT JOIN recent_activity ra
  ON ra.OwnerUserId = tu.UserId AND ra.rn = 1
LEFT JOIN tag_pop tpu
  ON POSITION(',' || tpu.TagName || ',' IN ',' || ra.Tags || ',') > 0
LEFT JOIN complex_calc cc
  ON cc.UserId = tu.UserId
ORDER BY tu.Reputation DESC, ra.LastActivityDate DESC
LIMIT 100;