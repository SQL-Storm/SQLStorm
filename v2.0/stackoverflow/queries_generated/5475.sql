-- {"query": "5475.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 756} 
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    b.TagBased
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '7 days'
),
TagCross as (
  SELECT
    t.TagName,
    COUNT(*) AS TagUseCount
  FROM Tags t
  GROUP BY t.TagName
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.ViewCount,
    r.Score,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.UserId,
    r.UserName,
    r.Reputation,
    r.Location,
    r.BadgeId,
    r.BadgeName,
    r.BadgeDate,
    r.TagBased,
    tc.TagName,
    tc.TagUseCount,
    -- window function: rank most active posts per day in recent week
    ROW_NUMBER() OVER (PARTITION BY DATE(r.CreationDate) ORDER BY r.ViewCount DESC, r.Score DESC) AS DayRank,
    -- correlated subquery: total comments on posts by same user
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = r.UserId) AS TotalCommentsByUser,
    -- correlated subquery with MAX over related posts (via PostLinks)
    (SELECT MAX(pl.CreationDate)
     FROM PostLinks pl
     WHERE pl.PostId = r.PostId OR pl.RelatedPostId = r.PostId) AS LastLinkedActivity
  FROM RecentActive r
  LEFT JOIN TagCross tc ON 1=1
)
SELECT
  cs.PostId,
  cs.PostTypeId,
  ptype.Name AS PostTypeName,
  cs.Title,
  cs.Tags,
  cs.TagName,
  cs.TagUseCount,
  cs.ViewCount,
  cs.Score,
  cs.CommentCount,
  cs.AnswerCount,
  cs.FavoriteCount,
  cs.UserId,
  cs.UserName,
  cs.Reputation,
  cs.Location,
  cs.UserCreationDate,
  cs.LastAccessDate,
  cs.BadgeName,
  cs.BadgeDate,
  cs.Class AS BadgeClass,
  cs.TagBased,
  cs.DayRank,
  cs.TotalCommentsByUser,
  cs.LastLinkedActivity,
  u2.DisplayName AS LastEditorName,
  p.LastEditorDisplayName,
  p.LastEditDate
FROM CorrelatedStats cs
LEFT JOIN Posts p ON cs.PostId = p.Id
LEFT JOIN PostTypes ptype ON p.PostTypeId = ptype.Id
LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
ORDER BY cs.DayRank, cs.PostId
LIMIT 100;