-- {"query": "50068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 962} 
WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 25
),
PostTags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.AcceptedAnswerId,
        p.PostTypeId,
        p.ParentId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Tags IS NOT NULL
),
UserActivityInPopularTags AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        q.Id AS QuestionId,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        (CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Users u
    JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    JOIN (
        SELECT DISTINCT PostId FROM PostTags pt JOIN PopularTags popt ON pt.TagName = popt.TagName WHERE pt.PostTypeId = 1
    ) AS PopularQuestions ON q.Id = PopularQuestions.PostId
    WHERE u.Reputation > 1000
),
UserAggregatedStats AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        SUM(AnswerScore) AS TotalAnswerScore,
        COUNT(AnswerId) AS TotalAnswers,
        SUM(IsAcceptedAnswer) AS TotalAcceptedAnswers,
        AVG(AnswerScore) AS AverageAnswerScore
    FROM UserActivityInPopularTags
    GROUP BY UserId, DisplayName, Reputation
),
UserTagBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges
    FROM Badges b
    JOIN PopularTags pt ON b.Name = pt.TagName
    WHERE b.TagBased = true
    GROUP BY b.UserId
),
RankedUsers AS (
    SELECT
        stats.UserId,
        stats.DisplayName,
        stats.Reputation,
        stats.TotalAnswerScore,
        stats.TotalAnswers,
        stats.TotalAcceptedAnswers,
        COALESCE(badges.GoldBadges, 0) AS GoldBadges,
        COALESCE(badges.SilverBadges, 0) AS SilverBadges,
        (stats.TotalAnswerScore * 0.4 + stats.TotalAcceptedAnswers * 25 + COALESCE(badges.GoldBadges, 0) * 100 + COALESCE(badges.SilverBadges, 0) * 50) AS InfluenceScore,
        ROW_NUMBER() OVER (ORDER BY (stats.TotalAnswerScore * 0.4 + stats.TotalAcceptedAnswers * 25 + COALESCE(badges.GoldBadges, 0) * 100 + COALESCE(badges.SilverBadges, 0) * 50) DESC) AS Rank
    FROM UserAggregatedStats stats
    LEFT JOIN UserTagBadges badges ON stats.UserId = badges.UserId
    WHERE stats.TotalAnswers > 10
)
SELECT
    ru.Rank,
    ru.DisplayName,
    ru.Reputation,
    ru.InfluenceScore,
    ru.TotalAnswers,
    ru.TotalAcceptedAnswers,
    ru.GoldBadges,
    ru.SilverBadges,
    (SELECT AVG(Score) FROM Comments c WHERE c.UserId = ru.UserId) AS AvgCommentScore,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.UserId = ru.UserId AND v.VoteTypeId = 2) AS LastUpvoteDate
FROM RankedUsers ru
WHERE ru.Rank <= 100 AND ru.InfluenceScore > 0
ORDER BY ru.Rank;