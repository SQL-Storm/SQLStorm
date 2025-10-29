-- {"query": "5412.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 844}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.ParentId,
    p.PostTypeId,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_posttype
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
RecentActive AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    u.Reputation,
    u.DisplayName,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rp.LastActivityDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity,
    CASE
      WHEN rp.PostTypeId = 1 THEN 'Question'
      WHEN rp.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS FriendlyPostType,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountTotal,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 8) AS AvgBounty
  FROM RankedPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  WHERE rp.rn_posttype IN (1, 2)
),
CrossLinkActivity AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.FriendlyPostType,
    ra.Reputation,
    ra.DisplayName,
    ra.DaysSinceLastActivity,
    COALESCE(vt.Name, 'Unknown') AS LatestVoteType,
    ra.CommentCountTotal,
    ra.AvgBounty,
    (SELECT COUNT(*) FROM PostLinks pl
     WHERE (pl.PostId = ra.PostId OR pl.RelatedPostId = ra.PostId)
       AND pl.LinkTypeId IN (1,3)) AS TotalLinks,
    (SELECT STRING_AGG(CONCAT('Post ', pl.RelatedPostId, '->', pl.PostId), '; ')
     FROM PostLinks pl
     WHERE pl.PostId = ra.PostId) AS LinkTrail,
    ra.LastActivityDate
  FROM RecentActive ra
  LEFT JOIN Votes v ON v.PostId = ra.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = ra.PostId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE ra.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
),
ComplexFilters AS (
  SELECT
    ca.PostId,
    ca.Title,
    ca.FriendlyPostType,
    ca.Reputation,
    ca.DisplayName,
    ca.DaysSinceLastActivity,
    ca.LatestVoteType,
    ca.CommentCountTotal,
    ca.AvgBounty,
    ca.TotalLinks,
    ca.LinkTrail,
    ca.LastActivityDate
  FROM CrossLinkActivity ca
  ORDER BY ca.DaysSinceLastActivity DESC, ca.Reputation DESC
)
SELECT
  cf.PostId,
  cf.Title,
  cf.FriendlyPostType,
  cf.Reputation,
  cf.DisplayName,
  cf.DaysSinceLastActivity,
  cf.LatestVoteType,
  cf.CommentCountTotal,
  cf.AvgBounty,
  cf.TotalLinks,
  cf.LinkTrail
FROM ComplexFilters cf
WHERE cf.DaysSinceLastActivity < 400
  AND (cf.Reputation IS NULL OR cf.Reputation > 100)
  AND (cf.TotalLinks >= 0)
ORDER BY cf.DaysSinceLastActivity DESC, cf.Reputation DESC
LIMIT 200;