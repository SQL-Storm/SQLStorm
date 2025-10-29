-- {"query": "5953.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 823} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS BountyActive,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    COUNT(*) AS PostCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPosts,
    SUM(p.ViewCount) AS ViewsAcrossTag,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  CROSS APPLY (VALUES (LEFT(p.Tags, 4000))) AS tsv(ts)
  CROSS APPLY (
    SELECT value AS TagName
    FROM string_to_table(p.Tags, ',') -- placeholder for compatibility; actual tag parsing may vary per DB
  ) AS t(TagName) 
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CorrelatedComments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  GROUP BY c.PostId
),
OuterPostLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
Combined AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.OwnerUserId,
    r.BountyActive,
    tta.UpVotesGiven,
    tta.DownVotesGiven,
    ca.CommentCount,
    ca.LastCommentDate,
    ulr.RelatedPostId,
    ulr.LinkTypeName
  FROM RecentHot r
  LEFT JOIN TopAuthors tta ON tta.UserId = r.OwnerUserId
  LEFT JOIN CorrelatedComments ca ON ca.PostId = r.PostId
  LEFT JOIN OuterPostLinks ulr ON ulr.PostId = r.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerUserId,
  (SELECT DisplayName FROM Users u WHERE u.Id = c.OwnerUserId) AS OwnerDisplayName,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.BountyActive,
  c.CommentCount,
  c.LastCommentDate,
  c.LinkTypeName,
  c.RelatedPostId
FROM Combined c
WHERE
  c.rn BETWEEN 1 AND 100
  OR c.LastActivityDate > NOW() - INTERVAL '7 days'
ORDER BY c.LastActivityDate DESC, c.Score DESC, c.ViewCount DESC
;