WITH Agg AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId, CAST(p.CreationDate AS DATE)
      ORDER BY p.Score DESC, p.ViewCount DESC
    ) AS RankInDayVsType,
    SUM(p.ViewCount) OVER (
      PARTITION BY p.PostTypeId, CAST(p.CreationDate AS DATE)
      ORDER BY p.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeViewsDay,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountExplicit
  FROM Posts p
  WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
),
Joined AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.LastEditorUserId,
    a.LastActivityDate,
    a.CommentCount,
    a.AnswerCount,
    a.FavoriteCount,
    a.ContentLicense,
    a.RankInDayVsType,
    a.CumulativeViewsDay,
    a.CommentCountExplicit,
    u.DisplayName AS OwnerDisplayName,
    l.DisplayName AS LastEditorDisplayName
  FROM Agg a
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  LEFT JOIN Users l ON l.Id = a.LastEditorUserId
),
Filtered AS (
  SELECT
    *
  FROM Joined
  WHERE
    PostTypeId = 1
    AND Score > 0
    AND (Tags ILIKE '%performance%' OR Title ILIKE '%benchmark%')
)
SELECT
  a.PostId,
  a.PostTypeId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.OwnerUserId,
  a.OwnerDisplayName,
  a.LastEditorUserId,
  a.LastEditorDisplayName,
  a.LastActivityDate,
  a.CommentCount,
  a.AnswerCount,
  a.FavoriteCount,
  a.ContentLicense,
  a.RankInDayVsType,
  a.CumulativeViewsDay,
  a.CommentCountExplicit,
  CASE
    WHEN a.ViewCount > 1000 THEN 'High traffic'
    WHEN a.ViewCount BETWEEN 100 AND 1000 THEN 'Medium traffic'
    ELSE 'Low traffic'
  END AS TrafficBand,
  (a.Score + COALESCE(B.BountyAmount, 0)) AS ScoreWithBounty
FROM Filtered a
LEFT JOIN (
  SELECT PostId, BountyAmount
  FROM Votes v
  WHERE v.VoteTypeId = 8
) B ON B.PostId = a.PostId
ORDER BY a.CumulativeViewsDay DESC, a.RankInDayVsType ASC
LIMIT 200;