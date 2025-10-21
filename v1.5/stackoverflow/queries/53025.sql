-- {"query": "53025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 592} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(pl.RelatedPostId) AS LinkCount,
        AVG(v.BountyAmount) AS AvgBounty
    FROM Tags t
    LEFT JOIN Posts po ON t.ExcerptPostId = po.Id
    LEFT JOIN PostLinks pl ON po.Id = pl.PostId
    LEFT JOIN Votes v ON po.Id = v.PostId AND v.VoteTypeId = 8
    GROUP BY t.TagName
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalScore,
    tu.Rank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount AS TopQuestionViews,
    tq.AnswerCount,
    tq.FavoriteCount,
    ts.TagName,
    ts.LinkCount,
    ts.AvgBounty,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = tu.UserId) AS TotalComments
FROM TopUsers tu
LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
LEFT JOIN TopQuestions tq ON tu.UserId = tq.OwnerUserId
LEFT JOIN TagStats ts ON ts.TagName = (SELECT TagName FROM Tags ORDER BY Count DESC LIMIT 1)
WHERE tu.Rank <= 100
ORDER BY tu.Rank;