-- {"query": "43064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 644} 

WITH TopAnswerers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2 AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        p.OwnerUserId
    ORDER BY 
        TotalScore DESC, AnswerCount DESC
    LIMIT 100
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
UserPosts AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ta.AnswerCount, 0) AS AnswerCount,
        COALESCE(ta.TotalScore, 0) AS TotalScore,
        COALESCE(ta.AvgScore, 0) AS AvgScore,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesGiven
    FROM 
        Users u
    LEFT JOIN 
        TopAnswerers ta ON u.Id = ta.OwnerUserId
    LEFT JOIN 
        UserBadges ub ON u.Id = ub.UserId
)
SELECT 
    up.Id,
    up.DisplayName,
    up.Reputation,
    up.AnswerCount,
    up.TotalScore,
    up.AvgScore,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.UpVotesGiven,
    up.DownVotesGiven,
    DENSE_RANK() OVER (ORDER BY up.TotalScore DESC, up.AnswerCount DESC) AS PerformanceRank
FROM 
    UserPosts up
WHERE 
    up.Reputation > 1000
ORDER BY 
    PerformanceRank;
