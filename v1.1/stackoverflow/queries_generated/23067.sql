-- {"query": "23067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 836} 

WITH ClosedQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(p.ClosedDate, p.CreationDate) AS EffectiveClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
),
ReopenedPosts AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastReopenDate,
        COUNT(DISTINCT ph.UserId) AS ReopenVoters
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 11
    GROUP BY ph.PostId
    HAVING COUNT(*) > 1
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetUpvotes,
        AVG(NULLIF(v.BountyAmount, 0)) AS AvgBounty
    FROM Votes v
    WHERE v.CreationDate > '2020-01-01'
    GROUP BY v.PostId
)
SELECT 
    cq.PostId,
    cq.Title,
    cq.Tags,
    COALESCE(SUBSTRING(cq.Tags, 2, LENGTH(cq.Tags) - 2), 'No Tags') AS CleanTags,
    u.DisplayName AS OwnerName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BadgeNames,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cq.PostId AND c.Score > 5) AS HighScoreComments,
    cv.NetUpvotes,
    cv.AvgBounty,
    rp.LastReopenDate,
    rp.ReopenVoters,
    CASE 
        WHEN cq.ViewCount > 10000 THEN 'High Views' 
        WHEN cq.ViewCount BETWEEN 1000 AND 10000 THEN 'Medium Views' 
        ELSE 'Low Views' 
    END AS ViewCategory,
    cq.RankByScore
FROM ClosedQuestions cq
LEFT JOIN ReopenedPosts rp ON cq.PostId = rp.PostId
INNER JOIN Posts p ON cq.PostId = p.Id
LEFT OUTER JOIN Users u ON p.OwnerUserId = u.Id
FULL OUTER JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN ComplexVotes cv ON cq.PostId = cv.PostId
WHERE cq.Score > 0 OR rp.ReopenVoters IS NOT NULL
UNION ALL
SELECT 
    pl.PostId,
    p.Title,
    p.Tags,
    COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), 'No Tags') AS CleanTags,
    NULL AS OwnerName,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BadgeNames,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pl.PostId AND c.Score > 5) AS HighScoreComments,
    NULL AS NetUpvotes,
    NULL AS AvgBounty,
    NULL AS LastReopenDate,
    NULL AS ReopenVoters,
    'Linked Duplicate' AS ViewCategory,
    NULL AS RankByScore
FROM PostLinks pl
INNER JOIN Posts p ON pl.RelatedPostId = p.Id
WHERE pl.LinkTypeId = 3 AND p.ClosedDate IS NULL
ORDER BY PostId DESC;
