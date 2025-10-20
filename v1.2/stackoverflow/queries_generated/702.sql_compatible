WITH RECURSIVE RecursiveCTE AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.Reputation,
        u.DisplayName,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        1 AS Level
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers

    UNION ALL

    SELECT
        p2.Id,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        p2.Tags,
        u2.Reputation,
        u2.DisplayName,
        r.Level + 1 AS rn,
        r.Level + 1 AS Level
    FROM Posts p2
    INNER JOIN RecursiveCTE r ON p2.ParentId = r.PostId
    LEFT JOIN Users u2 ON p2.OwnerUserId = u2.Id
    WHERE p2.PostTypeId = 2
      AND r.Level < 3
),
RankedPosts AS (
    SELECT
        PostId,
        PostTypeId,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        Tags,
        Reputation,
        DisplayName,
        Level,
        dense_rank() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, ViewCount DESC) AS ScoreRank
    FROM RecursiveCTE
),
FilteredPosts AS (
    SELECT *
    FROM RankedPosts
    WHERE ScoreRank <= 5
),
PostBadgesAgg AS (
    SELECT
        b.UserId,
        b.Class,
        count(*) AS BadgeCount
    FROM Badges b
    WHERE b.Class IN (1, 2, 3)
    GROUP BY b.UserId, b.Class
),
UserBadgeSummary AS (
    SELECT
        UserId,
        coalesce(sum(CASE WHEN Class = 1 THEN BadgeCount END), 0) AS GoldBadges,
        coalesce(sum(CASE WHEN Class = 2 THEN BadgeCount END), 0) AS SilverBadges,
        coalesce(sum(CASE WHEN Class = 3 THEN BadgeCount END), 0) AS BronzeBadges
    FROM PostBadgesAgg
    GROUP BY UserId
),
PostCommentsCount AS (
    SELECT
        c.PostId,
        count(*) AS TotalComments,
        count(CASE WHEN c.UserId IS NULL THEN 1 END) AS AnonymousComments,
        count(CASE WHEN c.UserId IS NOT NULL THEN 1 END) AS RegisteredComments
    FROM Comments c
    GROUP BY c.PostId
),
PostCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        count(*) AS CloseVotes
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
PostLinkAggregates AS (
    SELECT
        pl.PostId,
        count(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount,
        count(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
)
SELECT 
    fp.PostId,
    fp.PostTypeId,
    fp.OwnerUserId,
    u.DisplayName AS OwnerName,
    fp.Score,
    fp.ViewCount,
    fp.CreationDate,
    fp.Tags,
    fp.Reputation,
    coalesce(ubs.GoldBadges, 0) AS GoldBadges,
    coalesce(ubs.SilverBadges, 0) AS SilverBadges,
    coalesce(ubs.BronzeBadges, 0) AS BronzeBadges,
    coalesce(pc.TotalComments, 0) AS TotalComments,
    coalesce(pc.AnonymousComments, 0) AS AnonymousComments,
    coalesce(pc.RegisteredComments, 0) AS RegisteredComments,
    coalesce(pcr.CloseVotes, 0) AS CloseVotes,
    coalesce(plag.LinkedCount, 0) AS LinkedPosts,
    coalesce(plag.DuplicateCount, 0) AS DuplicatePosts,
    CASE 
        WHEN fp.Score > 100 AND fp.ViewCount > 10000 THEN 'High Impact'
        WHEN fp.Score BETWEEN 50 AND 100 AND fp.ViewCount BETWEEN 5000 AND 10000 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS ImpactCategory,
    substring(fp.Tags FROM '<([^>]+)>') AS FirstTag,
    (SELECT count(*) FROM Posts p3 WHERE p3.OwnerUserId = fp.OwnerUserId AND p3.PostTypeId = 1 AND p3.CreationDate < fp.CreationDate) AS PreviousQuestionsCount,
    (SELECT avg(Score) FROM Posts p4 WHERE p4.OwnerUserId = fp.OwnerUserId AND p4.PostTypeId = 2 AND p4.CreationDate < fp.CreationDate) AS AvgAnswerScoreBefore,
    row_number() OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.CreationDate) AS UserPostSequence,
    lag(fp.Score, 1, 0) OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.CreationDate) AS PrevPostScore,
    lead(fp.Score, 1, 0) OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.CreationDate) AS NextPostScore
FROM FilteredPosts fp
LEFT JOIN Users u ON u.Id = fp.OwnerUserId
LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = fp.OwnerUserId
LEFT JOIN PostCommentsCount pc ON pc.PostId = fp.PostId
LEFT JOIN PostCloseReasons pcr ON pcr.PostId = fp.PostId
LEFT JOIN PostLinkAggregates plag ON plag.PostId = fp.PostId
WHERE fp.Level = 1
  AND (fp.Tags IS NOT NULL AND fp.Tags LIKE '%<sql>%')

UNION

SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    u.Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS TotalComments,
    0 AS AnonymousComments,
    0 AS RegisteredComments,
    0 AS CloseVotes,
    0 AS LinkedPosts,
    0 AS DuplicatePosts,
    'No Data' AS ImpactCategory,
    NULL AS FirstTag,
    0 AS PreviousQuestionsCount,
    NULL AS AvgAnswerScoreBefore,
    0 AS UserPostSequence,
    0 AS PrevPostScore,
    0 AS NextPostScore
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.Tags IS NULL
ORDER BY OwnerUserId, CreationDate DESC
LIMIT 100;