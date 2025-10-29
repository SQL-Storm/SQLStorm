-- {"query": "5958.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 939}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    u.Location,
    u.CreationDate,
    u.LastAccessDate,
    u.WebsiteUrl,
    u.AboutMe,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
),
PostHist AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 16, 66) -- notable history events
),
LinkInfo AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Id IN (1, 3) -- Linked and Duplicate
),
Combined AS (
  SELECT
    rap.PostId,
    rap.Title,
    rap.Tags,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.OwnerUserId,
    rap.Score,
    rap.ViewCount,
    rap.CommentCount,
    rap.AnswerCount,
    up.DisplayName AS OwnerDisplayName,
    up.Reputation,
    up.Location,
    up.AccountId,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY rap.PostId), 0) AS UpVotesFromVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY rap.PostId), 0) AS DownVotesFromVotes,
    ci.TagName
  FROM RecentActivePosts rap
  LEFT JOIN Votes v ON v.PostId = rap.PostId
  LEFT JOIN Users up ON rap.OwnerUserId = up.Id
  LEFT JOIN TopTags ci ON POSITION(ci.TagName IN rap.Tags) > 0
  WHERE rap.ViewCount > 0
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Reputation,
  c.Location,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.UpVotesFromVotes,
  c.DownVotesFromVotes,
  c.TagName AS TopTag,
  ARRAY_AGG(DISTINCT bl.Name) FILTER (WHERE bl.Name IS NOT NULL) AS BadgeNames,
  (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.PostId) AS CommentCountTotal,
  (SELECT STRING_AGG(u2.DisplayName || ':' || CAST(u2.Reputation AS VARCHAR), '|' )
     FROM Votes v2 JOIN Users u2 ON v2.UserId = u2.Id WHERE v2.PostId = c.PostId) AS VotersInfo
FROM Combined c
LEFT JOIN Badges bl ON bl.UserId = c.OwnerUserId
GROUP BY
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.LastActivityDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Reputation,
  c.Location,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.UpVotesFromVotes,
  c.DownVotesFromVotes,
  c.TagName
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;