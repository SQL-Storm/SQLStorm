WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagTotal
  FROM Tags t
  GROUP BY t.TagName
),
UserReputationWindow AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.DisplayName,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id ASC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
InfluenceScore AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    (CASE
      WHEN p.PostTypeId = 1 THEN p.Score * 2
      WHEN p.PostTypeId = 2 THEN p.Score
      ELSE p.Score * 0.5
    END
    + COALESCE(v.BountyAmount, 0)) AS Influence
  FROM Posts p
  LEFT JOIN Votes v
    ON v.PostId = p.Id
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
Combined AS (
  SELECT
    rap.UserId,
    rap.Reputation,
    rap.DisplayName,
    COALESCE(i.Influence, 0) AS Influence
  FROM UserReputationWindow rap
  LEFT JOIN InfluenceScore i
    ON i.OwnerUserId = rap.UserId
  WHERE rap.rn <= 100
),
ComplexMetrics AS (
  SELECT
    pr.Id AS PostId,
    pr.OwnerUserId,
    pr.Title,
    pr.ViewCount,
    pr.Score,
    pr.CommentCount,
    pr.Tags,
    pr.LastActivityDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pr.Id) AS CommentCountTotal,
    (SELECT ARRAY_AGG(tp.Title) FROM PostLinks pl JOIN Posts tp ON pl.RelatedPostId = tp.Id WHERE pl.PostId = pr.Id) AS RelatedPostTitles
  FROM RecentActivePosts pr
  LEFT JOIN PostLinks pl ON pl.PostId = pr.Id
)
SELECT
  c.PostId,
  c.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  c.Title,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.Tags,
  c.LastActivityDate,
  c.CommentCountTotal,
  c.RelatedPostTitles,
  i.Influence
FROM ComplexMetrics c
LEFT JOIN Users u ON u.Id = c.OwnerUserId
LEFT JOIN Combined i ON i.UserId = c.OwnerUserId
WHERE
  c.ViewCount > 0
  AND (c.Score > 0 OR c.CommentCountTotal > 5)
  AND (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 2) > 0
GROUP BY
  c.PostId,
  c.OwnerUserId,
  u.DisplayName,
  c.Title,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.Tags,
  c.LastActivityDate,
  c.CommentCountTotal,
  c.RelatedPostTitles,
  i.Influence
ORDER BY c.LastActivityDate DESC, i.Influence DESC
LIMIT 100;