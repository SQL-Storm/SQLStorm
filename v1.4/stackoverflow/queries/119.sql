-- {"query": "119.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1732} 
WITH UserPostStats AS (
  SELECT u.Id AS UserId,
         COUNT(p.Id) AS PostCount,
         COALESCE(SUM(p.Score), 0) AS ScoreSum,
         MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
TagUsage AS (
  SELECT t.TagName AS Tag, COUNT(*) AS TagCount
  FROM Posts p
  CROSS JOIN LATERAL regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS TagName
  JOIN Tags t ON t.TagName = TagName.TagName
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
RecentVotes AS (
  SELECT p.Id AS PostId, COUNT(v.Id) AS VoteCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
  GROUP BY p.Id
),
TopPosts AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  COALESCE(u.DisplayName, CAST(u.Id AS VARCHAR(20))) AS UserDisplayName,
  u.Reputation,
  ups.PostCount AS UserPostCount,
  ups.ScoreSum AS UserScoreSum,
  ups.LastActivity AS LastUserActivity,
  tu.Tag AS TopTagUsed,
  tp.Score AS TopPostScore,
  rv.VoteCount AS RecentPostVotes
FROM Users u
LEFT JOIN UserPostStats ups ON ups.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT TagUsage.Tag, TagUsage.TagCount
  FROM TagUsage
  ORDER BY TagUsage.TagCount DESC
  LIMIT 1
) AS tu ON TRUE
LEFT JOIN LATERAL (
  SELECT tp.Score
  FROM TopPosts tp
  WHERE tp.OwnerUserId = u.Id
  ORDER BY tp.Score DESC
  LIMIT 1
) AS tp ON TRUE
LEFT JOIN RecentVotes rv ON TRUE
ORDER BY u.Reputation DESC, u.CreationDate ASC
LIMIT 100;