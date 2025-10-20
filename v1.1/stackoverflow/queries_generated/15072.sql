-- {"query": "15072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 170455, "output_tokens": 50161} 
WITH RankedQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        u.Reputation,
        DENSE_RANK() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) as TagScoreRank,
        FIRST_VALUE(p.Id) OVER (PARTITION BY p.Tags ORDER BY p.ViewCount DESC) as MostViewedPostInTag,
        COALESCE(
            (SELECT AVG(v.BountyAmount) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0) as AvgBounty
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
UserBadgeStats AS (
    SELECT 
        UserId, 
        COUNT(*) as TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) as SilverBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    rq.Id,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.AvgBounty,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    CASE 
        WHEN rq.Reputation > 10000 THEN 'High Rep'
        WHEN rq.Reputation > 5000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END as ReputationTier,
    ROUND(rq.ViewCount * 1.0 / NULLIF(rq.AnswerCount, 0), 2) as ViewsPerAnswer,
    rq.TagScoreRank,
    COALESCE((
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId = rq.Id AND pl.LinkTypeId = 3
    ), 0) as DuplicateCount
FROM RankedQuestions rq
LEFT JOIN UserBadgeStats ubs ON rq.OwnerUserId = ubs.UserId
WHERE 
    rq.TagScoreRank <= 10 
    AND rq.AvgBounty > 0
    AND (ubs.GoldBadges > 3 OR ubs.SilverBadges > 5)
ORDER BY 
    rq.Score DESC, 
    rq.ViewCount DESC
LIMIT 100;