WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        (u.UpVotes * 1.0 / NULLIF(u.UpVotes + u.DownVotes, 0)) * 100 AS ScoreRatio,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostType,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS ViewRank,
        /* compute tag count by counting occurrences of '><' plus 1 when tags not null/empty */
        CASE 
          WHEN p.Tags IS NULL OR LENGTH(p.Tags) = 0 THEN 0
          ELSE LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1
        END AS TagCount,
        COALESCE(ph.CloseReason, 'Not closed') AS CloseStatus
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT 
            ph_inner.PostId,
            MAX(crt.Name) AS CloseReason
        FROM PostHistory ph_inner
        JOIN CloseReasonTypes crt ON CAST(ph_inner.Comment AS INTEGER) = crt.Id
        WHERE ph_inner.PostHistoryTypeId = 10
        GROUP BY ph_inner.PostId
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
),
VoteAggregates AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS Downvotes,
        SUM(CASE WHEN VoteTypeId = 8 THEN COALESCE(BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM Votes
    GROUP BY PostId
)
SELECT 
    us.UserId,
    us.Reputation,
    pa.PostId,
    pa.PostType,
    pa.ViewRank,
    (va.Upvotes - va.Downvotes) AS NetVotes,
    (pa.Score * 0.5 + pa.ViewCount * 0.3 + pa.AnswerCount * 1.2) * CASE WHEN pa.CloseStatus = 'Not closed' THEN 1.5 ELSE 0.8 END AS EngagementScore,
    SUBSTR(pa.CloseStatus, 1, 3) || '...' AS CloseAbbr,
    CASE WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId IN (8,9)) THEN TRUE ELSE FALSE END AS HasBounty,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 1) AS LinkedPosts
FROM UserStats us
LEFT JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
LEFT JOIN VoteAggregates va ON pa.PostId = va.PostId
WHERE us.Reputation > 1000
  AND pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
  AND (us.GoldBadges > 0 OR us.SilverBadges > 5)

UNION ALL

SELECT 
    us.UserId,
    us.Reputation,
    CAST(NULL AS INTEGER) AS PostId,
    'N/A' AS PostType,
    CAST(NULL AS INTEGER) AS ViewRank,
    CAST(NULL AS INTEGER) AS NetVotes,
    us.ScoreRatio AS EngagementScore,
    CAST(NULL AS TEXT) AS CloseAbbr,
    FALSE AS HasBounty,
    CAST(NULL AS INTEGER) AS LinkedPosts
FROM UserStats us
WHERE us.Reputation <= 1000
ORDER BY EngagementScore DESC NULLS LAST, NetVotes DESC
LIMIT 100;