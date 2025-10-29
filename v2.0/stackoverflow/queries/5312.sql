-- {"query": "5312.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 890} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagSearch AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
DailyActivity AS (
  SELECT
    DATE(p.CreationDate) AS ActivityDay,
    COUNT(*) AS PostsCreated
  FROM Posts p
  GROUP BY DATE(p.CreationDate)
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    MAX(p.Score) AS PeakPostScore
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
CorrelatedSubquery AS (
  SELECT
    p.PostTypeId,
    p.Id AS PostId,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBountyAtPost
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
WindowedScores AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Score,
    SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingTopScore
  FROM Posts p
  WHERE p.Score IS NOT NULL
),
Joined AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.Tags,
    tt.TagName
  FROM RecentActivePosts rp
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName
  ) tt ON true
  WHERE rp.PostTypeId = 1
)
SELECT
  jp.PostId,
  jp.Title,
  jp.OwnerUserId,
  COALESCE(u.DisplayName, 'community') AS OwnerDisplayName,
  jp.CreationDate,
  jp.LastActivityDate,
  jp.ViewCount,
  jp.Score,
  jp.CommentCount,
  jp.Tags,
  jp.TagName,
  ds.AvgBountyAtPost,
  ws.RollingTopScore,
  ustats.Reputation,
  ustats.BadgeCount,
  d.ActivityDay,
  d.PostsCreated
FROM Joined jp
LEFT JOIN Users u ON u.Id = jp.OwnerUserId
LEFT JOIN CorrelatedSubquery ds ON ds.PostId = jp.PostId
LEFT JOIN WindowedScores ws ON ws.PostId = jp.PostId
LEFT JOIN UserStats ustats ON ustats.UserId = u.Id
LEFT JOIN DailyActivity d ON false
LEFT JOIN TagSearch t ON t.TagName = jp.TagName
ORDER BY jp.LastActivityDate DESC
LIMIT 200;