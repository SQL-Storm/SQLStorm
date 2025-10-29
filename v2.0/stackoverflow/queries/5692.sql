-- {"query": "5692.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1118}
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.DisplayName,
    u.Location,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate,
    bt.Name AS BadgeName,
    bt.Class AS BadgeClass
  FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges bt ON bt.UserId = u.Id
  WHERE
    p.LastActivityDate >= (CAST('2024-10-01' AS date) - INTERVAL '180 days')
),
PostMetrics AS (
  SELECT
    ra.PostId,
    ra.PostTypeId,
    ra.OwnerUserId,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Title,
    ra.Tags,
    ra.Score,
    ra.ViewCount,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.Reputation,
    ra.UserCreationDate,
    ra.DisplayName,
    ra.Location,
    vm.DistinctVoteTypes,
    MAX(CASE WHEN ra.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.PostId) AS HasUpvote,
    MAX(CASE WHEN ra.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.PostId) AS HasDownvote,
    MAX(CASE WHEN ra.BadgeClass = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.PostId) AS HasGoldBadge,
    MAX(CASE WHEN ra.BadgeClass = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.PostId) AS HasSilverBadge,
    MAX(CASE WHEN ra.BadgeClass = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.PostId) AS HasBronzeBadge
  FROM
    RecentActivity ra
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(DISTINCT VoteTypeId) AS DistinctVoteTypes
      FROM
        RecentActivity
      WHERE VoteTypeId IS NOT NULL
      GROUP BY PostId
    ) vm ON vm.PostId = ra.PostId
),
RelatedTop AS (
  SELECT
    rp.Id AS RelatedPostId,
    rp.Title AS RelatedTitle,
    rp.Tags AS RelatedTags,
    rp.CreationDate AS RelatedCreationDate,
    rp.ViewCount AS RelatedViews,
    rp.Score AS RelatedScore,
    ROW_NUMBER() OVER (PARTITION BY rp.Tags ORDER BY rp.Score DESC, rp.CreationDate DESC) AS rn
  FROM
    Posts rp
  WHERE
    NOT EXISTS (SELECT 1 FROM RecentActivity ra WHERE ra.PostId = rp.Id)
    AND rp.LastActivityDate >= (CAST('2024-10-01' AS date) - INTERVAL '90 days')
),
Final AS (
  SELECT
    pm.PostId,
    pm.PostTypeId,
    pm.OwnerUserId,
    pm.CreationDate,
    pm.LastActivityDate,
    pm.Title,
    pm.Tags,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.Reputation,
    pm.UserCreationDate,
    pm.DisplayName,
    pm.Location,
    pm.DistinctVoteTypes,
    pm.HasUpvote,
    pm.HasDownvote,
    pm.HasGoldBadge,
    pm.HasSilverBadge,
    pm.HasBronzeBadge,
    LOWER(REGEXP_REPLACE(pm.Tags, '[<>]', '', 'g')) AS NormalizedTags,
    RANK() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.LastActivityDate DESC) AS OwnerRecentRank,
    (SELECT COUNT(*) FROM RelatedTop r WHERE r.RelatedTags = pm.Tags AND r.rn <= 10) AS TopRelatedCount,
    pm.PostId AS SyntheticKey
  FROM
    PostMetrics pm
    LEFT JOIN RelatedTop rt ON rt.rn = 1
  WHERE
    pm.LastActivityDate >= (CAST('2024-10-01' AS date) - INTERVAL '365 days')
)
SELECT DISTINCT
  f.PostId,
  f.Title,
  f.Tags,
  f.ViewCount,
  f.Score,
  f.DistinctVoteTypes,
  f.HasUpvote,
  f.HasBronzeBadge,
  f.NormalizedTags,
  f.OwnerRecentRank,
  f.TopRelatedCount
FROM
  Final f
ORDER BY
  f.OwnerRecentRank ASC,
  f.Score DESC
LIMIT 100;