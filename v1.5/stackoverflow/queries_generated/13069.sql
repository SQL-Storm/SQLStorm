-- {"query": "13069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 777} 

WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        SUM(COALESCE(b.Class, 0)) AS BadgeScore,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(b.Class, 0)) DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
),
UserPosts AS (
    SELECT 
        p.OwnerUserId, 
        COUNT(*) AS PostCount, 
        SUM(p.Score) AS TotalScore,
        AVG(NULLIF(p.ViewCount, 0)) AS AvgViewCount
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY 
        p.OwnerUserId
),
PostComments AS (
    SELECT 
        p.Id AS PostId, 
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id
),
ComplexAggregation AS (
    SELECT 
        tu.Id, 
        tu.DisplayName,
        tu.BadgeScore,
        COALESCE(up.PostCount, 0) AS PostCount,
        COALESCE(up.TotalScore, 0) AS TotalScore,
        COALESCE(up.AvgViewCount, 0) AS AvgViewCount,
        COALESCE(pc.CommentCount, 0) AS CommentCount,
        pc.LastCommentDate,
        DENSE_RANK() OVER (PARTITION BY up.OwnerUserId ORDER BY COALESCE(up.TotalScore, 0) DESC) AS PostRank
    FROM 
        TopUsers tu
    LEFT JOIN 
        UserPosts up ON tu.Id = up.OwnerUserId
    LEFT JOIN 
        PostComments pc ON up.OwnerUserId = pc.PostId
    WHERE 
        tu.UserRank <= 100
)
SELECT 
    ca.Id,
    ca.DisplayName,
    ca.BadgeScore,
    ca.PostCount,
    ca.TotalScore,
    ca.AvgViewCount,
    ca.CommentCount,
    CASE 
        WHEN ca.LastCommentDate IS NULL THEN 'No Comments'
        ELSE CONCAT('Last comment on ', TO_CHAR(ca.LastCommentDate, 'YYYY-MM-DD'))
    END AS LastCommentInfo,
    (
        SELECT 
            STRING_AGG(CONCAT(pt.Name, ': ', COUNT(*)), '; ')
        FROM 
            Posts p
        JOIN 
            PostTypes pt ON p.PostTypeId = pt.Id
        WHERE 
            p.OwnerUserId = ca.Id
        GROUP BY 
            pt.Name
    ) AS PostTypeDistribution
FROM 
    ComplexAggregation ca
WHERE 
    ca.PostRank <= 5
ORDER BY 
    ca.BadgeScore DESC, ca.TotalScore DESC;
