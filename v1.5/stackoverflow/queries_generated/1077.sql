-- {"query": "1077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 435} 

WITH UserBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostScores AS (
    SELECT 
        p.OwnerUserId,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.OwnerUserId
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        COALESCE(ps.TotalScore, 0) AS TotalScore,
        COALESCE(ps.PostCount, 0) AS PostCount,
        COALESCE(ps.AvgScore, 0) AS AvgScore,
        RANK() OVER (ORDER BY COALESCE(ps.TotalScore, 0) DESC) AS ScoreRank
    FROM 
        Users u
    LEFT JOIN 
        UserBadges ub ON u.Id = ub.UserId
    LEFT JOIN 
        PostScores ps ON u.Id = ps.OwnerUserId
)
SELECT 
    u.UserId,
    u.BadgeCount,
    u.TotalScore,
    u.PostCount,
    u.AvgScore,
    CASE 
        WHEN u.AvgScore > 50 THEN 'Expert'
        WHEN u.AvgScore BETWEEN 20 AND 50 THEN 'Intermediate'
        ELSE 'Novice'
    END AS SkillLevel,
    pt.Name AS PostTypeName
FROM 
    UserEngagement u
LEFT JOIN 
    PostTypes pt ON u.PostCount > 0
WHERE 
    u.BadgeCount > 0 
    OR u.PostCount > 0
ORDER BY 
    u.ScoreRank, u.TotalScore DESC;

