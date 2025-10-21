WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(p.Id) AS TotalQuestions,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
        AVG(u.Reputation) AS AvgReputation,
        -- include WebsiteUrl and DisplayName for downstream concatenation
        MAX(u.WebsiteUrl) AS WebsiteUrl,
        MAX(u.DisplayName) AS DisplayName
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 9
    GROUP BY 
        u.Id
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    us.TotalQuestions,
    us.TotalBounty,
    us.AvgReputation,
    STRING_AGG(DISTINCT CONCAT('<a href="', us.WebsiteUrl, '">', us.DisplayName, '</a>'), ', ') AS UserLinks
FROM 
    RankedPosts rp
JOIN 
    UserStats us ON rp.OwnerUserId = us.UserId
LEFT JOIN 
    Comments c ON c.PostId = rp.PostId
WHERE 
    rp.rn = 1
GROUP BY 
    rp.PostId, rp.Title, rp.Score, rp.ViewCount, rp.CreationDate, us.TotalQuestions, us.TotalBounty, us.AvgReputation
HAVING 
    COUNT(c.Id) > 5
ORDER BY 
    rp.Score DESC, rp.CreationDate DESC;