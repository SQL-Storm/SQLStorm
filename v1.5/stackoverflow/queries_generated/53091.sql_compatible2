WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.BountyAmount) AS TotalBountyEarned
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    GROUP BY 
        u.Id, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.UserId
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagUsage,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(p.Id) > 1000
),
UserActivity AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY 
        ph.UserId
)
SELECT 
    u.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgPostScore,
    ups.TotalBountyEarned,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ucs.CommentCount,
    ucs.AvgCommentScore,
    ua.EditCount,
    ua.LastEditDate,
    STRING_AGG(tt.TagName, ', ') AS TopTagsUsed,
    RANK() OVER (ORDER BY ups.Reputation DESC) AS ReputationRank,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ups.AvgPostScore) = 0
        -- Placeholder to indicate standard SQL handling; actual percentile_cont without window over may vary by dialect
FROM 
    Users u
JOIN 
    UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN 
    UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN 
    UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN 
    UserActivity ua ON u.Id = ua.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
    TopTags tt ON p.Tags LIKE '%' || tt.TagName || '%' AND tt.TagRank <= 10
WHERE 
    ups.Reputation > 10000
    AND u.CreationDate >= '2010-01-01'
    AND EXISTS (
        SELECT 1 
        FROM PostLinks pl 
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    )
GROUP BY 
    u.DisplayName, ups.Reputation, ups.QuestionCount, ups.AnswerCount, ups.AvgPostScore, ups.TotalBountyEarned,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ucs.CommentCount, ucs.AvgCommentScore,
    ua.EditCount, ua.LastEditDate, ups.UserId
HAVING 
    COUNT(DISTINCT tt.TagName) >= 3
ORDER BY 
    ReputationRank ASC
LIMIT 100;