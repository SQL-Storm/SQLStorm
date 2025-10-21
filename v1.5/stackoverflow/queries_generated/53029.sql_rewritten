-- {"query": "53029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 731} 
WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) AS RankInTag
    FROM 
        Users u
    INNER JOIN 
        Posts p ON u.Id = p.OwnerUserId
    INNER JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1  -- Questions
        AND p.CreationDate >= '2020-01-01'
    GROUP BY 
        u.Id, u.Reputation, t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM 
        Votes v
    WHERE 
        v.CreationDate >= '2020-01-01'
    GROUP BY 
        v.PostId
),
CommentStats AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
PostHistoryMetrics AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
)
SELECT 
    au.UserId,
    au.Reputation,
    au.PostCount,
    au.TotalScore,
    au.RankInTag,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    SUM(va.Upvotes) AS TotalUpvotes,
    SUM(va.Downvotes) AS TotalDownvotes,
    AVG(cs.AvgCommentScore) AS OverallAvgCommentScore,
    MAX(phm.LastEditDate) AS LatestEdit
FROM 
    ActiveUsers au
LEFT JOIN 
    BadgeSummary bs ON au.UserId = bs.UserId
INNER JOIN 
    Posts p ON au.UserId = p.OwnerUserId
LEFT JOIN 
    VoteAnalysis va ON p.Id = va.PostId
LEFT JOIN 
    CommentStats cs ON p.Id = cs.PostId
LEFT JOIN 
    PostHistoryMetrics phm ON p.Id = phm.PostId
WHERE 
    au.RankInTag <= 10
GROUP BY 
    au.UserId, au.Reputation, au.PostCount, au.TotalScore, au.RankInTag,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
ORDER BY 
    au.TotalScore DESC
LIMIT 100;