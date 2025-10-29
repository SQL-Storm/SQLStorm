WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    ARRAY_AGG(DISTINCT t.Name) AS TypeNames
  FROM Posts p
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
    p.OwnerUserId, p.Tags, p.PostTypeId, p.AcceptedAnswerId
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.ProfileImageUrl,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
DeepLinkPosts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.PostTypeId,
    rp.AcceptedAnswerId,
    tr.Name AS PostTypeName,
    le.DisplayName AS LastEditorName,
    COALESCE(p.Body, '') AS Body,
    COALESCE(p.LastEditDate, rp.CreationDate) AS LastEditApprox
  FROM RankedPosts rp
  LEFT JOIN PostTypes tr ON rp.PostTypeId = tr.Id
  LEFT JOIN Posts p ON rp.PostId = p.Id
  LEFT JOIN Users le ON p.LastEditorUserId = le.Id
),
Windowed AS (
  SELECT
    dp.PostId,
    dp.Title,
    dp.CreationDate,
    dp.LastActivityDate,
    dp.Score,
    dp.ViewCount,
    dp.OwnerUserId,
    dp.Tags,
    dp.PostTypeId,
    dp.AcceptedAnswerId,
    dp.PostTypeName,
    dp.LastEditorName,
    dp.Body,
    dp.LastEditApprox,
    SUM(dp.Score) OVER (PARTITION BY dp.PostTypeId ORDER BY dp.LastActivityDate ROWS BETWEEN 364 PRECEDING AND CURRENT ROW) AS RollingYearScore,
    AVG(dp.ViewCount) OVER (PARTITION BY dp.PostTypeId) AS AvgViewsPerType
  FROM DeepLinkPosts dp
),
Qualified AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.OwnerUserId,
    w.Tags,
    w.PostTypeId,
    w.AcceptedAnswerId,
    w.PostTypeName,
    w.LastEditorName,
    w.Body,
    w.LastEditApprox,
    w.RollingYearScore,
    w.AvgViewsPerType,
    CASE
      WHEN w.Score >= 5 THEN 'High'
      WHEN w.Score >= 0 THEN 'Moderate'
      ELSE 'Low'
    END AS ScoreBand,
    CASE
      WHEN w.Body LIKE '%performance%' OR w.Body LIKE '%benchmark%' THEN TRUE
      ELSE FALSE
    END AS MentionsBenchmark
  FROM Windowed w
)
SELECT
  q.PostId,
  q.Title,
  q.PostTypeName,
  q.LastActivityDate,
  q.LastEditApprox,
  q.Score,
  q.ViewCount,
  q.RollingYearScore,
  q.AvgViewsPerType,
  q.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  q.Tags,
  q.Body,
  q.LastEditorName,
  q.ScoreBand,
  q.MentionsBenchmark,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS UpvoteCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 3) AS DownvoteCount,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 8) AS BountyStartDate
FROM Qualified q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
ORDER BY q.LastActivityDate DESC, q.RollingYearScore DESC
LIMIT 200;