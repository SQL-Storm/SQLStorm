-- {"query": "5735.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 798} 
WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe, u.ProfileImageUrl,
    u.EmailHash, u.AccountId
),
RecentActivity AS (
  SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.LastPostDate,
    ROW_NUMBER() OVER (PARTITION BY u.UserId ORDER BY p.LastActivityDate DESC) AS rn,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.Id AS PostId,
    p.PostTypeId,
    p.Score AS PostScore,
    p.ViewCount
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate > DATEADD(day, -30, CURRENT_TIMESTAMP)
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.WikiPostId,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.Count > 0
),
CrossJoinStats AS (
  SELECT
    up.DisplayName AS UserDisplayName,
    up.Reputation,
    up.PostCount,
    up.ScoreSum,
    up.AvgPostScore,
    ra.LastPostDate,
    ra.Title AS LastPostTitle,
    ra.Tags AS LastPostTags,
    ra.PostId AS LastPostId,
    ra.PostTypeId AS LastPostTypeId,
    ra.PostScore AS LastPostScore,
    ra.ViewCount AS LastPostViews,
    NULL AS Placeholder
  FROM UserActivity up
  LEFT JOIN RecentActivity ra ON ra.UserId = up.UserId AND ra.rn = 1
)
SELECT
  cjs.UserDisplayName,
  cjs.Reputation,
  cjs.PostCount,
  cjs.ScoreSum,
  cjs.AvgPostScore,
  cjs.LastPostDate,
  cjs.LastPostTitle,
  cjs.LastPostTags,
  cjs.LastPostId,
  cjs.LastPostTypeId,
  cjs.LastPostScore,
  cjs.LastPostViews,
  ht.TagName AS TopTag,
  ht.Count AS TagCount,
  ht.WikiPostId,
  ht.ExcerptPostId
FROM CrossJoinStats cjs
LEFT JOIN (
  SELECT
    -- correlate a dynamic top tag per user via a window over their last 50 posts
    p.OwnerUserId AS UserId,
    t.TagName,
    t.Count,
    t.WikiPostId,
    t.ExcerptPostId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY t.Count DESC) AS rn
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%' -- approximate tag relation
  WHERE p.OwnerUserId IS NOT NULL
) ht ON ht.UserId = (SELECT Id FROM Users u WHERE u.DisplayName = cjs.UserDisplayName LIMIT 1)
         AND ht.rn = 1
ORDER BY cjs.Reputation DESC, cjs.PostCount DESC
LIMIT 100;