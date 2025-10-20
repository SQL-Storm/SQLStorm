WITH RECURSIVE RecursiveCTE AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.PostTypeId,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.AcceptedAnswerId,
           dense_rank() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostRank,
           1 AS Level
      FROM Posts p
     WHERE p.PostTypeId = 1
       AND p.Score > 5
    UNION ALL
    SELECT p2.Id,
           p2.OwnerUserId,
           p2.PostTypeId,
           p2.Score,
           p2.ViewCount,
           p2.CreationDate,
           p2.AcceptedAnswerId,
           dense_rank() OVER (PARTITION BY p2.OwnerUserId ORDER BY p2.CreationDate) AS PostRank,
           r.Level + 1
      FROM Posts p2
      JOIN RecursiveCTE r ON p2.OwnerUserId = r.OwnerUserId
     WHERE p2.PostTypeId = 2
       AND p2.ParentId = r.Id
       AND p2.Score > r.Score / 2
       AND r.Level < 3
), UserBadgeCounts AS (
    SELECT b.UserId,
           b.Class,
           COUNT(*) AS BadgeCount
      FROM Badges b
     GROUP BY b.UserId, b.Class
), LatestComments AS (
    SELECT c.PostId,
           c.Id AS CommentId,
           c.UserId AS CommentUserId,
           c.CreationDate AS CommentDate,
           row_number() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
      FROM Comments c
), UserReputationWindow AS (
    SELECT u.Id,
           u.Reputation,
           u.CreationDate,
           avg(u.Reputation) OVER (ORDER BY u.CreationDate ROWS BETWEEN 999 PRECEDING AND CURRENT ROW) AS AvgReputationLast1000Users,
           count(*) OVER () AS TotalUsers
      FROM Users u
), DuplicateLinks AS (
    SELECT pl.PostId,
           pl.RelatedPostId
      FROM PostLinks pl
      JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
     WHERE lt.Name = 'Duplicate'
)
SELECT
    rcte.Id AS PostId,
    rcte.PostTypeId,
    rcte.Score,
    rcte.ViewCount,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubg_gold.BadgeCount, 0) AS GoldBadges,
    COALESCE(ubg_silver.BadgeCount, 0) AS SilverBadges,
    COALESCE(ubg_bronze.BadgeCount, 0) AS BronzeBadges,
    lc.CommentId AS LatestCommentId,
    lc.CommentUserId,
    lc.CommentDate,
    rcte.Level AS DepthLevel,
    CASE WHEN dup.PostId IS NOT NULL THEN 'Has Duplicates' ELSE 'No Duplicates' END AS DuplicateStatus,
    'Score/ViewRatio: ' || round((CAST(rcte.Score AS numeric) / NULLIF(rcte.ViewCount, 0)), 4) AS ScoreViewRatio,
    rcte.PostRank,
    urw.AvgReputationLast1000Users,
    urw.TotalUsers,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND position('http' IN u.WebsiteUrl) = 1 THEN 'Valid Website' ELSE 'No Website / Invalid' END AS WebsiteStatus,
    substr(COALESCE(CAST(rcte.AcceptedAnswerId AS text), 'None'), 1, 10) AS AcceptedAnswerDisplay
  FROM RecursiveCTE rcte
  JOIN Users u ON u.Id = rcte.OwnerUserId
  LEFT JOIN UserBadgeCounts ubg_gold ON ubg_gold.UserId = u.Id AND ubg_gold.Class = 1
  LEFT JOIN UserBadgeCounts ubg_silver ON ubg_silver.UserId = u.Id AND ubg_silver.Class = 2
  LEFT JOIN UserBadgeCounts ubg_bronze ON ubg_bronze.UserId = u.Id AND ubg_bronze.Class = 3
  LEFT JOIN LatestComments lc ON lc.PostId = rcte.Id AND lc.rn = 1
  LEFT JOIN DuplicateLinks dup ON dup.PostId = rcte.Id
  JOIN UserReputationWindow urw ON urw.Id = u.Id
 WHERE rcte.Score >
       (SELECT avg(p2.Score) * 0.8 FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.OwnerUserId = rcte.OwnerUserId)
   AND (substr(u.DisplayName, 1, 1) IN ('A','B','C') OR u.Location IS NOT NULL)
 ORDER BY rcte.Level DESC, rcte.Score DESC
 LIMIT 100;