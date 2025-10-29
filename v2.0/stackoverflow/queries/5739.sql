-- {"query": "5739.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 823}
WITH
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(COALESCE(u.LastAccessDate, u.CreationDate) AS DATE)
      ORDER BY u.Reputation DESC, u.LastAccessDate DESC
    ) AS DayRank
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.CreationDate,
    p.LastActivityDate,
    CASE
      WHEN p.PostTypeId = 1 THEN (COALESCE(p.ViewCount,0) * 2 + COALESCE(p.Score,0) * 3)
      ELSE (COALESCE(p.ViewCount,0) + COALESCE(p.Score,0))
    END AS EngagementScore,
    CASE
      WHEN p.ParentId IS NULL THEN 0
      ELSE 1
    END AS IsReply
  FROM Posts p
  WHERE p.ClosedDate IS NULL
    AND p.ContentLicense IS NOT NULL
),
LatestRevisions AS (
  SELECT
    ph.PostId,
    ph.Id AS RevisionId,
    ph.UserId AS EditorUserId,
    ph.CreationDate AS RevisionDate,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (1,2,5,10,11,16,24,66)
    AND ph.CreationDate = (
      SELECT MAX(ph2.CreationDate)
      FROM PostHistory ph2
      WHERE ph2.PostId = ph.PostId
        AND ph2.PostHistoryTypeId = ph.PostHistoryTypeId
    )
),
LinkedPosts AS (
  SELECT
    p.Id AS PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate AS LinkCreationDate
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN Posts p ON pl.PostId = p.Id
)
SELECT
  au.UserId,
  au.DisplayName,
  au.Reputation,
  au.LastAccessDate,
  au.DayRank,
  pm.PostId,
  pm.Title,
  pm.Tags,
  pm.EngagementScore,
  pm.ViewCount,
  pm.Score,
  pm.CommentCount,
  pm.CreationDate,
  pm.LastActivityDate,
  rr.RevisionId AS LatestRevisionId,
  rr.EditorUserId AS LatestEditorUserId,
  rr.RevisionDate AS LatestRevisionDate,
  rr.Comment AS LatestRevisionComment,
  lp.RelatedPostId,
  lp.LinkTypeName,
  lp.LinkCreationDate
FROM ActiveUsers au
JOIN PostMetrics pm ON pm.OwnerUserId = au.UserId
LEFT JOIN LatestRevisions rr ON rr.PostId = pm.PostId
LEFT JOIN LinkedPosts lp ON lp.PostId = pm.PostId
WHERE
  au.DayRank = 1
  AND pm.EngagementScore > 0
ORDER BY au.Reputation DESC, pm.EngagementScore DESC, pm.LastActivityDate DESC
LIMIT 100;