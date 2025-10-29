WITH RankedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS RNPerDay
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
ExpensiveJoins AS (
  SELECT
    r.Id,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v
     WHERE v.PostId = r.Id AND v.VoteTypeId = 2) AS UpModTotal,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id) AS CommentCountTotal,
    LENGTH(r.Tags) AS TagsLength
  FROM RankedPosts r
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  WHERE r.RNPerDay = 1
),
TagStats AS (
  SELECT
    e.Id,
    e.Title,
    e.CreationDate,
    e.Score,
    e.ViewCount,
    e.Tags,
    e.OwnerUserId,
    e.LastActivityDate,
    e.CommentCount,
    e.AnswerCount,
    e.FavoriteCount,
    e.Reputation,
    e.DisplayName,
    e.Location,
    e.AccountId,
    e.UpModTotal,
    e.CommentCountTotal,
    e.TagsLength,
    AVG(e.Score) OVER (PARTITION BY e.OwnerUserId) AS AvgScoreByOwner,
    SUM(e.ViewCount) OVER (PARTITION BY e.OwnerUserId) AS TotalViewsByOwner
  FROM ExpensiveJoins e
)
SELECT
  ts.Id,
  ts.Title,
  ts.CreationDate,
  ts.Score,
  ts.ViewCount,
  ts.Tags,
  ts.OwnerUserId,
  ts.LastActivityDate,
  ts.CommentCount,
  ts.AnswerCount,
  ts.FavoriteCount,
  ts.Reputation,
  ts.DisplayName,
  ts.Location,
  ts.AccountId,
  ts.UpModTotal,
  ts.CommentCountTotal,
  ts.TagsLength,
  ts.AvgScoreByOwner,
  ts.TotalViewsByOwner,
  CASE WHEN ts.ViewCount = 0 THEN 0
       ELSE (ts.CommentCountTotal + ts.AnswerCount) * 1.0 / ts.ViewCount
  END AS EngagementRatio,
  CASE
    WHEN ts.Score > 50
      AND ts.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
      AND ts.Tags LIKE '%<%>%'
    THEN 'HighQualityActive'
    ELSE 'Moderate'
  END AS QualityCategory
FROM TagStats ts
ORDER BY ts.TotalViewsByOwner DESC, ts.Score DESC, ts.LastActivityDate DESC
LIMIT 200;