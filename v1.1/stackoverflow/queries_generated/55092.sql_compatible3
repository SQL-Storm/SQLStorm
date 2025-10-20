WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreQuestions,
        AVG(p.ViewCount) AS AvgViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.AnswerCount) AS MedianAnswers,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestions,
        COUNT(*) AS TotalQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
AnswerMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(p.Score) AS AvgScore,
        COUNT(*) AS TotalAnswers
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (1,2,3)
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagUseCount,
        COUNT(DISTINCT pl.PostId) AS LinkedPosts,
        COUNT(DISTINCT pl.RelatedPostId) AS RelatedPosts,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN PostLinks pl ON pl.LinkTypeId = 1 AND (pl.PostId = t.ExcerptPostId OR pl.RelatedPostId = t.WikiPostId)
    GROUP BY t.TagName, t.Count
),
UserTagActivity AS (
    SELECT
        pu.OwnerUserId AS UserId,
        TRIM(BOTH '<>' FROM split_part(split_part(pu.Tags, '><', seq.pos), '><', 1)) AS RawTag,
        COUNT(*) AS TagUsageCount
    FROM Posts pu
    JOIN (
        -- generate numbers up to a reasonable max tag count per post, adjust 10 if needed
        SELECT 1 AS pos UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) AS seq(pos) ON seq.pos <= 1 + LENGTH(pu.Tags) - LENGTH(REPLACE(pu.Tags, '><', ''))
    WHERE pu.PostTypeId = 1 AND pu.Tags IS NOT NULL
    GROUP BY pu.OwnerUserId, RawTag
),
TopUserTagStats AS (
    SELECT
        uta.UserId,
        t.TagName,
        SUM(uta.TagUsageCount) AS TotalTagUses,
        ROW_NUMBER() OVER (PARTITION BY uta.UserId ORDER BY SUM(uta.TagUsageCount) DESC) AS TagRank
    FROM UserTagActivity uta
    JOIN TagPopularity t ON t.TagName = uta.RawTag
    GROUP BY uta.UserId, t.TagName
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.RepRank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    qm.TotalQuestions,
    qm.HighScoreQuestions,
    qm.AvgViews,
    qm.MedianAnswers,
    qm.TotalFavorites,
    qm.ClosedQuestions,
    am.TotalAnswers,
    am.UpVotesReceived,
    am.DownVotesReceived,
    am.AcceptedAnswers,
    am.AvgScore,
    COALESCE(
        (SELECT 
             CASE WHEN COUNT(*) = 0 THEN '[]' 
                  ELSE '[' || STRING_AGG('{"Tag":"' || REPLACE(t.TagName, '"', '\"') || '","Uses":' || CAST(t.TotalTagUses AS VARCHAR) || '}', ',') || ']' 
             END
         FROM TopUserTagStats t
         WHERE t.UserId = tu.UserId AND t.TagRank <= 3
        ),
        '[]'
    ) AS TopTags
FROM TopUsers tu
LEFT JOIN UserBadgeStats ub ON ub.UserId = tu.UserId
LEFT JOIN QuestionMetrics qm ON qm.UserId = tu.UserId
LEFT JOIN AnswerMetrics am ON am.UserId = tu.UserId
ORDER BY tu.RepRank
LIMIT 100;