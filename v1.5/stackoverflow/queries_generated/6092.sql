-- {"query": "6092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 901} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.PostTypeId,
    p.Tags,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
TopQuestions AS (
  SELECT
    r.Id,
    r.Title,
    r.OwnerUserId,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.PostTypeId,
    r.Tags,
    r.OwnerDisplayName
  FROM RecentTopPosts r
  WHERE r.PostTypeId = 1 AND r.rn = 1
),
TopTagWikis AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 0
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate >= NOW() - INTERVAL '365 days') AS PostsLastYear,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.CreationDate >= NOW() - INTERVAL '365 days') AS VotesLastYear
  FROM Users u
),
CrossLinking AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
ComplexPostHistory AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Text,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 16, 52, 53, 66) -- selected history types to benchmark
),
Aggregated AS (
  SELECT
    q.Id AS QuestionId,
    q.Title AS QuestionTitle,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.CreationDate AS QuestionCreated,
    q.ViewCount,
    q.Score,
    q.Tags,
    COALESCE(b.Name, 'NoBadge') AS RecentBadge,
    ua.Reputation,
    ua.PostsLastYear,
    ua.VotesLastYear,
    COUNT(DISTINCT cl.RelatedPostId) AS LinkedCount,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM TopQuestions q
  LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
  LEFT JOIN UserActivity ua ON ua.UserId = q.OwnerUserId
  LEFT JOIN CrossLinking cl ON cl.PostId = q.Id
  LEFT JOIN Comments c ON c.PostId = q.Id
  GROUP BY
    q.Id, q.Title, q.OwnerUserId, q.OwnerDisplayName, q.CreationDate, q.ViewCount, q.Score, q.Tags, b.Name, ua.Reputation, ua.PostsLastYear, ua.VotesLastYear
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (ORDER BY a.QuestionCreated DESC, a.ViewCount DESC) AS rn
  FROM Aggregated a
)
SELECT
  w.QuestionId,
  w.QuestionTitle,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.QuestionCreated,
  w.ViewCount,
  w.Score,
  w.Tags,
  w.RecentBadge,
  w.Reputation,
  w.PostsLastYear,
  w.VotesLastYear,
  w.LinkedCount,
  w.CommentCount
FROM Windowed w
WHERE w.rn <= 100
ORDER BY w.QuestionCreated DESC, w.ViewCount DESC;