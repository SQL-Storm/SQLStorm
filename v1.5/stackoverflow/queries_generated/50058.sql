-- {"query": "50058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1161} 

WITH UserContributionStats AS (
    -- Aggregate user activities over the last 5 years
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoriteCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year') AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
BadgeAndCommentStats AS (
    -- Calculate badge and comment counts separately
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    GROUP BY u.Id
),
RecentActivity AS (
    -- Identify users who were active in the last year
    SELECT DISTINCT UserId FROM (
        SELECT OwnerUserId AS UserId FROM Posts WHERE LastActivityDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
        UNION ALL
        SELECT UserId FROM Comments WHERE CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
        UNION ALL
        SELECT UserId FROM Votes WHERE CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
    ) AS Activity
    WHERE UserId IS NOT NULL
),
UserInfluenceScore AS (
    -- Calculate a composite influence score
    SELECT
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        (
            (ucs.AnswerCount * 10) +
            (ucs.TotalAnswerScore * 2) +
            (ucs.QuestionCount * 5) +
            (CAST(ucs.TotalQuestionViewCount AS BIGINT) / 100) +
            (ucs.TotalFavoriteCount * 3) +
            (COALESCE(bcs.CommentCount, 0) * 0.5) +
            (COALESCE(bcs.GoldBadges, 0) * 100) +
            (COALESCE(bcs.SilverBadges, 0) * 25) +
            (COALESCE(bcs.BronzeBadges, 0) * 5)
        ) AS InfluenceScore,
        CASE
            WHEN ucs.QuestionCount > 0 THEN ucs.AnswerCount::decimal / ucs.QuestionCount
            ELSE 0
        END AS AnswerQuestionRatio,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ucs.CreationDate)) / 86400 AS AccountAgeDays
    FROM UserContributionStats ucs
    JOIN BadgeAndCommentStats bcs ON ucs.UserId = bcs.UserId
    WHERE ucs.UserId IN (SELECT UserId FROM RecentActivity)
)
-- Final ranking and selection of top users with detailed metrics
SELECT
    uis.DisplayName,
    uis.Reputation,
    uis.InfluenceScore,
    DENSE_RANK() OVER (ORDER BY uis.InfluenceScore DESC, uis.Reputation DESC) AS UserRank,
    uis.InfluenceScore / uis.AccountAgeDays AS DailyInfluence,
    uis.AnswerQuestionRatio,
    (SELECT STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName)
     FROM Posts P
     JOIN Tags T ON T.Id IN (SELECT CAST(val AS INT) FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS val)
     WHERE P.OwnerUserId = uis.UserId AND P.PostTypeId = 1
     LIMIT 5) AS TopTags,
    LAG(uis.InfluenceScore, 1, 0) OVER (ORDER BY uis.InfluenceScore DESC, uis.Reputation DESC) - uis.InfluenceScore AS ScoreDiffToNext
FROM UserInfluenceScore uis
WHERE uis.InfluenceScore > 500
ORDER BY UserRank ASC, uis.Reputation DESC
LIMIT 150;
