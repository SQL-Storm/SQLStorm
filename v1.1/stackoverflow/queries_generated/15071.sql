-- {"query": "15071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 727}
WITH RankedQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Tags, 
        p.Score, 
        p.ViewCount,
        u.Reputation,
        AVG(p.Score) OVER (PARTITION BY LEFT(p.Tags, CHARINDEX('>', p.Tags + '>') - 1)) AS AvgTagScore,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags + '>') - 2) ORDER BY p.Score DESC) AS TagRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.Score > 0 
        AND p.ViewCount > 100
        AND u.Reputation > 1000
),
UserBadgeStats AS (
    SELECT 
        UserId, 
        COUNT(DISTINCT CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN Class = 3 THEN Id END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    rq.Id AS QuestionId,
    rq.Title,
    rq.Tags,
    rq.Score,
    rq.ViewCount,
    rq.Reputation,
    rq.AvgTagScore,
    rq.TagRank,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = rq.Id), 0
    ) AS CommentCount,
    CASE 
        WHEN rq.Score > rq.AvgTagScore THEN 'High Performer'
        WHEN rq.Score = rq.AvgTagScore THEN 'Average Performer'
        ELSE 'Low Performer'
    END AS PerformanceCategory,
    ROUND(
        rq.Score * LOG(rq.ViewCount + 1) / 
        NULLIF(rq.Reputation, 0), 
        2
    ) AS EngagementIndex
FROM 
    RankedQuestions rq
LEFT JOIN 
    UserBadgeStats ubs ON rq.OwnerUserId = ubs.UserId
WHERE 
    rq.TagRank <= 10 
    AND (ubs.GoldBadges > 0 OR ubs.SilverBadges > 5)
ORDER BY 
    EngagementIndex DESC
LIMIT 100;
