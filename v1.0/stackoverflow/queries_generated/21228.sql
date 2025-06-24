WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 -- Only Questions
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(b.Class = 1)::int, 0) AS GoldBadges,
        COALESCE(SUM(b.Class = 2)::int, 0) AS SilverBadges,
        COALESCE(SUM(b.Class = 3)::int, 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS QuestionCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY 
        u.Id
    HAVING 
        COUNT(DISTINCT p.Id) > 10 -- More than 10 Questions
),
UserPostStats AS (
    SELECT 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.DisplayName
    HAVING 
        SUM(p.ViewCount) > 1000 -- Popular users with over 1000 views
),
RecentResponses AS (
    SELECT 
        p.Id AS PostId,
        COALESCE(EXTRACT(EPOCH FROM p.LastActivityDate - p.CreationDate), 0) AS TimeToResponse,
        u.DisplayName AS Responder
    FROM 
        Posts p
    INNER JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 2 -- Answers
        AND p.CreationDate > NOW() - INTERVAL '1 month' -- Answers from the last month
)
SELECT 
    t.UserId,
    t.DisplayName,
    t.Reputation,
    COALESCE(t.GoldBadges, 0) AS GoldBadges,
    COALESCE(t.SilverBadges, 0) AS SilverBadges,
    COALESCE(t.BronzeBadges, 0) AS BronzeBadges,
    up.TotalPosts,
    up.AvgPostScore,
    up.ClosedPosts,
    rp.ScoreRank,
    rr.TimeToResponse,
    rr.Responder
FROM 
    TopUsers t
LEFT JOIN 
    UserPostStats up ON up.DisplayName = t.DisplayName
LEFT JOIN 
    RankedPosts rp ON rp.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = t.UserId AND PostTypeId = 1 LIMIT 1)
LEFT JOIN 
    RecentResponses rr ON rr.Responder = t.DisplayName
WHERE 
    (up.TotalPosts IS NOT NULL AND up.AvgPostScore > 2) OR 
    ((t.GoldBadges + t.SilverBadges + t.BronzeBadges) > 3 AND rr.TimeToResponse < 3600)
ORDER BY 
    t.Reputation DESC,
    up.AvgPostScore DESC
LIMIT 10;
