-- {"query": "107.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2325} 
WITH UserTopQ AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
LatestQ AS (
  SELECT *
  FROM UserTopQ
  WHERE rn = 1
),
UserInfo AS (
  SELECT Id, DisplayName, Reputation
  FROM Users
  WHERE Reputation > 1000
),
Combined AS (
  -- Primary set: latest question per active user
  SELECT
    l.PostId,
    l.OwnerUserId,
    ui.DisplayName AS UserDisplayName,
    l.Title,
    l.LastActivityDate,
    l.Score,
    l.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = l.PostId) AS CommentCount,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = l.PostId AND v.VoteTypeId = 2) AS LastUpvoteDate
  FROM LatestQ l
  JOIN UserInfo ui ON l.OwnerUserId = ui.Id

  UNION ALL

  -- Secondary set: most recently edited answers by highly reputed users, via similar shape
  SELECT
    a.PostId,
    a.OwnerUserId,
    ui.DisplayName AS UserDisplayName,
    a.Title,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.PostId) AS CommentCount,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 2) AS LastUpvoteDate
  FROM (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.LastActivityDate, p.Score, p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    ORDER BY p.LastActivityDate DESC
    LIMIT 500
  ) a
  JOIN UserInfo ui ON a.OwnerUserId = ui.Id
)
SELECT
  c.PostId,
  c.UserDisplayName,
  c.Title,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.LastUpvoteDate,
  pl.LinkTypeId,
  rpt.Id AS RelatedPostId,
  rpt.Title AS RelatedPostTitle,
  t.TagName
FROM Combined c
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN Posts rpt ON rpt.Id = pl.RelatedPostId
LEFT JOIN Tags t ON t.ExcerptPostId = c.PostId
ORDER BY c.LastActivityDate DESC
LIMIT 100;