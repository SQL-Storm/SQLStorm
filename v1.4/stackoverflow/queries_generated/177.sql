-- {"query": "177.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2318} 
WITH
RecentPosts AS (
  SELECT Id, OwnerUserId, PostTypeId, Score, CreationDate
  FROM Posts
  WHERE CreationDate >= now() - interval '180 days'
),
UserStats AS (
  SELECT u.Id AS UserId, u.DisplayName,
         MAX(rp.CreationDate) AS LastPostDate,
         COUNT(rp.Id) AS PostWindowCount,
         COALESCE(SUM(rp.Score),0) AS ScoreWindowSum,
         COALESCE(AVG(rp.Score),0) AS ScoreWindowAvg
  FROM Users u
  LEFT JOIN RecentPosts rp ON rp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
BadgeStats AS (
  SELECT b.UserId, COUNT(*) AS BadgesEarned, MAX(b.Date) AS LatestBadge
  FROM Badges b
  GROUP BY b.UserId
),
VoteAggregation AS (
  SELECT v.UserId, v.PostId, v.VoteTypeId, v.CreationDate
  FROM Votes v
  WHERE v.VoteTypeId IN (2,3,10) -- UpMod, DownMod, Deletion
),
Combined AS (
  SELECT us.UserId, us.DisplayName, us.LastPostDate, us.PostWindowCount, us.ScoreWindowSum, us.ScoreWindowAvg,
         COALESCE(bs.BadgesEarned,0) AS Badges, bs.LatestBadge,
         COUNT(va.PostId) FILTER (WHERE va.VoteTypeId = 2) AS UpVotesGiven,
         COUNT(va.PostId) FILTER (WHERE va.VoteTypeId = 3) AS DownVotesGiven,
         MAX(va.CreationDate) AS LastVoteDate
  FROM UserStats us
  LEFT JOIN BadgeStats bs ON bs.UserId = us.UserId
  LEFT JOIN VoteAggregation va ON va.UserId = us.UserId
  GROUP BY us.UserId, us.DisplayName, us.LastPostDate, us.PostWindowCount, us.ScoreWindowSum, us.ScoreWindowAvg, bs.Badges, bs.LatestBadge
)
SELECT *
FROM Combined
ORDER BY ScoreWindowAvg DESC NULLS LAST
LIMIT 100;