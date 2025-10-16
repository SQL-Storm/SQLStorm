WITH
RecentPosts AS (
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
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days')
),
OwnerRecentComments AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.LastActivityDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.UserId = rp.OwnerUserId) AS OwnerCommentCount
  FROM RecentPosts rp
  WHERE rp.rn_owner = 1
),
-- Aggregate vote info per post to avoid treating Votes rows as single aggregated row
PostVoteAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownCount,
    SUM(COALESCE(v.BountyAmount, 0)) AS BountyAmount
  FROM Votes v
  GROUP BY v.PostId
),
ScoreFrame AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.Title,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    COALESCE(oc.OwnerCommentCount, 0) AS OwnerCommentCount,
    (COALESCE(pv.UpCount, 0) - COALESCE(pv.DownCount, 0)) AS NetVotesFromPost,
    (
      COALESCE(rp.ViewCount, 0) * 0.25
      + COALESCE(rp.Score, 0) * 1.75
      + COALESCE(pv.BountyAmount, 0) * 0.5
      + COALESCE(oc.OwnerCommentCount, 0) * 2.0
    ) AS CompositeScore
  FROM RecentPosts rp
  LEFT JOIN PostVoteAgg pv ON pv.PostId = rp.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = rp.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN OwnerRecentComments oc ON oc.PostId = rp.PostId
  WHERE rp.OwnerUserId IS NOT NULL
),
Filtered AS (
  SELECT
    sf.PostId,
    sf.OwnerUserId,
    sf.Title,
    sf.LastActivityDate,
    sf.CompositeScore,
    sf.NetVotesFromPost,
    sf.OwnerCommentCount
  FROM ScoreFrame sf
  WHERE sf.CompositeScore > 0
    AND sf.OwnerCommentCount >= 0
),
Ranked AS (
  SELECT
    f.PostId,
    f.OwnerUserId,
    f.Title,
    f.LastActivityDate,
    f.CompositeScore,
    f.NetVotesFromPost,
    f.OwnerCommentCount,
    ROW_NUMBER() OVER (ORDER BY f.CompositeScore DESC, f.LastActivityDate DESC, f.PostId ASC) AS rr
  FROM Filtered f
)
SELECT
  r.PostId,
  r.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  r.Title,
  r.LastActivityDate,
  r.CompositeScore,
  r.NetVotesFromPost,
  r.OwnerCommentCount,
  u.Reputation,
  u.CreationDate
FROM Ranked r
JOIN Users u ON u.Id = r.OwnerUserId
WHERE r.rr <= 100
ORDER BY r.CompositeScore DESC, r.LastActivityDate DESC, r.PostId ASC;