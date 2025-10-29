-- {"query": "5122.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1099} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount
  FROM Tags t
  WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
),
AuthorStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS TotalUserUpVotes
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl, u.AboutMe
),
RecentPostLinks AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.CreationDate >= NOW() - INTERVAL '60 days'
),
CorrelatedPostStats AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
    STRING_AGG(t.TagName, ',') AS AllTags
  FROM RecentActivePosts rp
  LEFT JOIN Votes v ON v.PostId = rp.Id
  LEFT JOIN UnnestTagList(rp.Tags) t ON true
  GROUP BY
    rp.Id, rp.Title, rp.PostTypeId, rp.OwnerUserId, rp.CreationDate,
    rp.LastActivityDate, rp.ViewCount, rp.Score, rp.AnswerCount, rp.CommentCount
),
-- Helper function simulation: split Tags into rows (not all DBs support). 
-- If not available, replace with a text-based extraction as a placeholder.
TagExtraction AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.Tags,
    rp.AllTags
  FROM CorrelatedPostStats rp
)
SELECT
  -- Outer join across activity, author stats, and tag context
  rp.PostId,
  rp.Title,
  pt.Name AS PostType,
  au.DisplayName AS Author,
  au.Reputation AS AuthorReputation,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.ViewCount,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.AllTags,
  vb.Name AS LastEditor,
  vb.LastEditDate,
  not_null(vb.Id) AS HasLastEditor,
  (CASE WHEN rp.Score > 0 THEN 'Positive' WHEN rp.Score < 0 THEN 'Negative' ELSE 'Neutral' END) AS ScoreTrend,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountTotal,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = rp.PostId AND v2.VoteTypeId = 2) AS UpVotesOnPost,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = rp.PostId AND v2.VoteTypeId = 3) AS DownVotesOnPost
FROM
  (SELECT * FROM RecentPostLinks) AS l
  RIGHT JOIN Posts rp ON rp.Id = l.PostId
  LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
  LEFT JOIN Users au ON rp.OwnerUserId = au.Id
  LEFT JOIN Users vb ON rp.LastEditorUserId = vb.Id
  LEFT JOIN TagExtraction te ON te.PostId = rp.Id
ORDER BY rp.LastActivityDate DESC
LIMIT 200;