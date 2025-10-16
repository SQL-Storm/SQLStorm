WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    WHERE 
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH
),
PostSummary AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
        AND p.PostTypeId IN (1, 2)
    GROUP BY 
        p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.CreationDate
),
UserPosts AS (
    SELECT 
        tu.Id AS UserId,
        tu.DisplayName,
        tu.ReputationRank,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(ps.Score), 0) AS TotalScore,
        AVG(ps.CommentCount) AS AvgComments
    FROM 
        TopUsers tu
    LEFT JOIN 
        PostSummary ps ON tu.Id = ps.OwnerUserId
    WHERE 
        tu.ReputationRank <= 100
    GROUP BY 
        tu.Id, tu.DisplayName, tu.ReputationRank
),
TopBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.ReputationRank,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    up.AvgComments,
    COALESCE(tb.GoldBadges, 0) AS GoldBadges,
    COALESCE(tb.SilverBadges, 0) AS SilverBadges,
    COALESCE(tb.BronzeBadges, 0) AS BronzeBadges,
    (up.DisplayName || ' has ' || up.QuestionCount || ' questions, ' || up.AnswerCount || ' answers, and a total score of ' || up.TotalScore) AS UserSummary
FROM 
    UserPosts up
LEFT JOIN 
    TopBadges tb ON up.UserId = tb.UserId
ORDER BY 
    up.TotalScore DESC, up.AvgComments DESC
LIMIT 10;