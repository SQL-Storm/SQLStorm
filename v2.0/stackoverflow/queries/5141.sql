-- {"query": "5141.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 864}
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    p.Tags,
    COALESCE(pf.LastEditDate, p.LastActivityDate) AS LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        COALESCE(p.LastActivityDate, p.CreationDate) DESC,
        p.Score DESC,
        p.ViewCount DESC
    ) AS rn_type
  FROM Posts p
  LEFT JOIN (
    SELECT
      p2.Id AS PostId,
      MAX(p2.LastEditDate) AS LastEditDate
    FROM Posts p2
    GROUP BY p2.Id
  ) pf ON pf.PostId = p.Id
  WHERE p.PostTypeId IN (1,2,5)
),
CommentCounts AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  WHERE c.PostId IS NOT NULL
  GROUP BY c.PostId
),
PostLinksExpanded AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
UserProfiles AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.WebsiteUrl,
    u.Location,
    u.AboutMe,
    u.LastAccessDate
  FROM Users u
),
AuthorMetrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsByUser,
    SUM(COALESCE(p.Score,0)) AS ScoreByUser,
    AVG(COALESCE(p.ViewCount,0)) AS AvgViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
)
SELECT
  ra.PostId,
  ra.Title,
  ra.PostTypeId,
  ra.CreationDate,
  ra.OwnerUserId,
  ra.ViewCount,
  ra.Score,
  ra.AnswerCount,
  ra.Tags,
  ra.LastActivityDate,
  cc.CommentCount,
  ul.DisplayName AS OwnerDisplayName,
  ul.Reputation,
  ul.WebsiteUrl,
  ul.Location,
  nm.PostsByUser,
  nm.ScoreByUser,
  nm.AvgViews,
  ple.LinkTypeName AS RelatedLinkTypeName
FROM RecentActivity ra
LEFT JOIN CommentCounts cc ON cc.PostId = ra.PostId
LEFT JOIN PostLinksExpanded ple ON ple.PostId = ra.PostId
LEFT JOIN UserProfiles ul ON ul.UserId = ra.OwnerUserId
LEFT JOIN (
  SELECT
    a.UserId,
    a.PostsByUser,
    a.ScoreByUser,
    a.AvgViews
  FROM AuthorMetrics a
  GROUP BY a.UserId, a.PostsByUser, a.ScoreByUser, a.AvgViews
) nm ON nm.UserId = ra.OwnerUserId
LEFT JOIN Tags t ON 1=0
ORDER BY ra.LastActivityDate DESC
LIMIT 100;