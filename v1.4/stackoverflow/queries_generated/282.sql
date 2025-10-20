-- {"query": "282.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10971} 
WITH RecentPerUser AS (
  SELECT p.OwnerUserId AS UserId,
         CONCAT(p.Title, ' (', CONVERT(varchar(19), p.LastActivityDate, 120), ')') AS MostRecentPostInfo,
         p.LastActivityDate AS MostRecentPostDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
UserTotals AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(p.Id) AS PostCount,
         SUM(p.Score) AS ScoreSum,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTagsPerUser AS (
  SELECT UserId, TagName, TagCount,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
  FROM (
     SELECT p.OwnerUserId AS UserId, t.TagName, COUNT(*) AS TagCount
     FROM Posts p
     LEFT JOIN Tags t ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
     WHERE p.OwnerUserId IS NOT NULL
     GROUP BY p.OwnerUserId, t.TagName
  ) s
)
SELECT
  ut.UserId,
  ut.DisplayName,
  ut.Reputation,
  rp.MostRecentPostInfo AS MostRecentPostInfo,
  rp.MostRecentPostDate AS MostRecentPostDate,
  ut.PostCount,
  ut.ScoreSum,
  ut.QuestionCount,
  ut.UpVotes,
  ut.DownVotes,
  tt.TagName AS MostUsedTag,
  tt.TagCount
FROM UserTotals ut
LEFT JOIN RecentPerUser rp ON rp.UserId = ut.UserId AND rp.rn = 1
LEFT JOIN TopTagsPerUser tt ON tt.UserId = ut.UserId AND tt.rn = 1
WHERE ut.Reputation >= 10000
UNION ALL
SELECT
  ut.UserId,
  ut.DisplayName,
  ut.Reputation,
  rp.MostRecentPostInfo AS MostRecentPostInfo,
  rp.MostRecentPostDate AS MostRecentPostDate,
  ut.PostCount,
  ut.ScoreSum,
  ut.QuestionCount,
  ut.UpVotes,
  ut.DownVotes,
  tt.TagName AS MostUsedTag,
  tt.TagCount
FROM UserTotals ut
LEFT JOIN RecentPerUser rp ON rp.UserId = ut.UserId AND rp.rn = 1
LEFT JOIN TopTagsPerUser tt ON tt.UserId = ut.UserId AND tt.rn = 1
WHERE ut.Reputation < 10000;