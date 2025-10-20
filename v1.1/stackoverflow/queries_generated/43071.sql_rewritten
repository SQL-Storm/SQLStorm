-- {"query": "43071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 624} 
WITH UserActivityMetrics AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, COUNT(DISTINCT b.Id) DESC) AS Ranking
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY 
        u.Id
),
TopPerformingUsers AS (
    SELECT 
        UserId,
        PostsCount,
        BadgesCount,
        AvgPostScore,
        GoldBadges,
        SilverBadges,
        BronzeBadges
    FROM 
        UserActivityMetrics
    WHERE 
        Ranking <= 10
)
SELECT 
    u.DisplayName,
    tpu.PostsCount,
    tpu.AvgPostScore,
    tpu.BadgesCount,
    tpu.GoldBadges,
    tpu.SilverBadges,
    tpu.BronzeBadges,
    COUNT(DISTINCT ph.Id) AS PostEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostCloseVotes,
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostReopenVotes
FROM 
    TopPerformingUsers tpu
JOIN 
    Users u ON tpu.UserId = u.Id
LEFT JOIN 
    PostHistory ph ON tpu.UserId = ph.UserId
WHERE 
    ph.CreationDate >= cast('2024-10-01' as date) - INTERVAL '6 months'
GROUP BY 
    u.DisplayName, tpu.PostsCount, tpu.AvgPostScore, tpu.BadgesCount, tpu.GoldBadges, tpu.SilverBadges, tpu.BronzeBadges
ORDER BY 
    tpu.PostsCount DESC, tpu.BadgesCount DESC;