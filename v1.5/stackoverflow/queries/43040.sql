WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        u.Location,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    WHERE 
        u.Reputation > 1000
),
ActivePosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName AS OwnerDisplayName,
        u.Id AS OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
),
CommentStats AS (
    SELECT 
        p.Id AS PostId, 
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    ap.Title,
    ap.CreationDate,
    ap.Score,
    ap.ViewCount,
    ap.AnswerCount,
    ap.CommentCount,
    cs.TotalComments,
    cs.AverageCommentScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges
FROM 
    TopUsers tu
JOIN 
    ActivePosts ap ON tu.Id = ap.OwnerUserId
LEFT JOIN 
    CommentStats cs ON ap.Id = cs.PostId
LEFT JOIN 
    UserBadges ub ON tu.Id = ub.UserId
WHERE 
    tu.ReputationRank <= 100
ORDER BY 
    ap.Score DESC, 
    tu.Reputation DESC
LIMIT 50;