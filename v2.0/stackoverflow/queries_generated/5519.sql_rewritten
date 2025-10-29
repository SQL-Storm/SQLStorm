-- {"query": "5519.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 807} 
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagPostCount
  FROM Tags t
  GROUP BY t.TagName
  HAVING SUM(t.Count) > 100
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostsCreated,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
CrossJoinStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.LastActivityDate,
    r.PostTypeId,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    CASE
      WHEN r.ViewCount > 1000 THEN 'VeryViewed'
      WHEN r.ViewCount BETWEEN 100 AND 1000 THEN 'ModeratelyViewed'
      ELSE 'LowViewed'
    END AS ViewBand,
    CASE
      WHEN r.Score >= 10 THEN 'Hot'
      WHEN r.Score >= 0 THEN 'Neutral'
      ELSE 'Cold'
    END AS ScoreBand,
    ROW_NUMBER() OVER (PARTITION BY r.PostTypeId ORDER BY r.LastActivityDate DESC) AS rn
  FROM RecentActive r
),
Filtered AS (
  SELECT *
  FROM CrossJoinStats
  WHERE rn <= 5
),
Joined AS (
  SELECT
    f.PostId,
    f.Title,
    f.CreationDate,
    f.OwnerUserId,
    f.Score,
    f.ViewCount,
    f.Tags,
    f.LastActivityDate,
    f.PostTypeId,
    f.AnswerCount,
    f.CommentCount,
    f.FavoriteCount,
    f.ViewBand,
    f.ScoreBand,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COALESCE(vt.Name, 'UnknownVote') AS LastVoteType
  FROM Filtered f
  LEFT JOIN Votes v ON v.PostId = f.PostId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  LEFT JOIN Users u ON u.Id = f.OwnerUserId
  WHERE f.PostTypeId IN (1, 2) -- focus on Q&A types
    AND (f.Tags ILIKE '%performance%' OR f.Tags ILIKE '%benchmark%')
)
SELECT
  m.PostId,
  m.Title,
  m.CreationDate,
  m.OwnerUserId,
  m.OwnerDisplayName,
  m.Reputation,
  m.Score,
  m.ViewCount,
  m.Tags,
  m.LastActivityDate,
  m.PostTypeId,
  m.AnswerCount,
  m.CommentCount,
  m.FavoriteCount,
  m.ViewBand,
  m.ScoreBand,
  m.LastVoteType,
  COALESCE(b.Name, 'NoBadge') AS BadgeName,
  b.Date AS BadgeDate
FROM Joined m
LEFT JOIN Badges b ON b.UserId = m.OwnerUserId AND b.Date = (
  SELECT MAX(Date) FROM Badges bb WHERE bb.UserId = m.OwnerUserId
)
ORDER BY m.LastActivityDate DESC
LIMIT 100;