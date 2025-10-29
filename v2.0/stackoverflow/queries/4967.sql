-- {"query": "4967.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1241} 
WITH UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
TopUsers AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY upa.TotalPosts DESC, upa.AverageScore DESC) AS RowNum,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        upa.TotalPosts,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AverageScore,
        COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AverageCommentScore, 0) AS AverageCommentScore,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus
    FROM Users u
    LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    WHERE u.Reputation > 1000
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AverageScore,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalComments,
    tu.AverageCommentScore,
    tu.UserUpVotes,
    tu.UserDownVotes,
    tu.WebsiteStatus,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND Score < 0) AS NegativeScorePosts,
    CASE
        WHEN tu.TotalComments > 500 AND tu.AverageCommentScore > 5 THEN 'Highly Engaged Commenter'
        WHEN tu.QuestionCount > 100 AND tu.AnswerCount > 200 THEN 'Prolific Contributor'
        ELSE 'Standard User'
    END AS UserProfileType,
    CASE
        WHEN tu.TotalPosts BETWEEN 100 AND 500 THEN 'Mid-Tier Contributor'
        WHEN tu.TotalPosts > 500 THEN 'High-Tier Contributor'
        ELSE 'Emerging Contributor'
    END AS PostVolumeTier
FROM TopUsers tu
WHERE tu.RowNum BETWEEN 51 AND 100
UNION ALL
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AverageScore,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalComments,
    tu.AverageCommentScore,
    tu.UserUpVotes,
    tu.UserDownVotes,
    tu.WebsiteStatus,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND Score < 0) AS NegativeScorePosts,
    CASE
        WHEN tu.TotalComments > 500 AND tu.AverageCommentScore > 5 THEN 'Highly Engaged Commenter'
        WHEN tu.QuestionCount > 100 AND tu.AnswerCount > 200 THEN 'Prolific Contributor'
        ELSE 'Standard User'
    END AS UserProfileType,
    CASE
        WHEN tu.TotalPosts BETWEEN 100 AND 500 THEN 'Mid-Tier Contributor'
        WHEN tu.TotalPosts > 500 THEN 'High-Tier Contributor'
        ELSE 'Emerging Contributor'
    END AS PostVolumeTier
FROM TopUsers tu
WHERE tu.RowNum IN (SELECT RelatedPostId FROM PostLinks WHERE LinkTypeId = 3 AND PostId = 12345)
ORDER BY Reputation DESC;