-- {"query": "50095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1123} 

WITH HighScoreQuestions AS (
    SELECT
        p.Id,
        p.CreationDate,
        p.OwnerUserId
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND p.Score > 150
        AND p.AnswerCount > 5
        AND p.FavoriteCount > 50
        AND p.CreationDate >= '2020-01-01'
),
QuestionAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        q.Id AS QuestionId,
        q.CreationDate AS QuestionCreationDate
    FROM Posts a
    JOIN HighScoreQuestions q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
),
UserAnswerMetrics AS (
    SELECT
        qa.OwnerUserId,
        EXTRACT(YEAR FROM qa.AnswerCreationDate) AS ActivityYear,
        COUNT(*) AS NumAnswers,
        SUM(qa.AnswerScore) AS TotalAnswerScore,
        AVG(qa.AnswerScore) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (qa.AnswerCreationDate - qa.QuestionCreationDate))) / 3600.0 AS AvgHoursToAnswer,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM QuestionAnswers qa
    LEFT JOIN Votes v ON qa.AnswerId = v.PostId
    GROUP BY qa.OwnerUserId, EXTRACT(YEAR FROM qa.AnswerCreationDate)
),
UserBadgeMetrics AS (
    SELECT
        b.UserId,
        EXTRACT(YEAR FROM b.Date) AS BadgeYear,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= '2020-01-01'
    GROUP BY b.UserId, EXTRACT(YEAR FROM b.Date)
),
CombinedMetrics AS (
    SELECT
        uam.OwnerUserId,
        uam.ActivityYear,
        u.DisplayName,
        u.Reputation,
        uam.NumAnswers,
        uam.TotalAnswerScore,
        uam.AvgAnswerScore,
        uam.AvgHoursToAnswer,
        uam.TotalUpvotes,
        uam.TotalDownvotes,
        COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
        (
            SELECT STRING_AGG(DISTINCT t.TagName, ', ')
            FROM Posts p_tags
            JOIN QuestionAnswers qa_tags ON p_tags.Id = qa_tags.QuestionId
            CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(p_tags.Tags, 2, LENGTH(p_tags.Tags) - 2), '><')) AS t(TagName)
            WHERE qa_tags.OwnerUserId = uam.OwnerUserId
              AND EXTRACT(YEAR FROM qa_tags.AnswerCreationDate) = uam.ActivityYear
        ) AS TagsAnswered
    FROM UserAnswerMetrics uam
    JOIN Users u ON uam.OwnerUserId = u.Id
    LEFT JOIN UserBadgeMetrics ubm ON uam.OwnerUserId = ubm.UserId AND uam.ActivityYear = ubm.BadgeYear
    WHERE uam.NumAnswers > 2 AND uam.TotalAnswerScore > 50
),
RankedUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER(
            PARTITION BY ActivityYear
            ORDER BY TotalAnswerScore DESC, GoldBadges DESC, TotalUpvotes DESC, AvgHoursToAnswer ASC
        ) as YearlyRank
    FROM CombinedMetrics
)
SELECT
    ru.ActivityYear,
    ru.YearlyRank,
    ru.DisplayName,
    ru.Reputation,
    ru.NumAnswers,
    ru.TotalAnswerScore,
    ru.AvgAnswerScore,
    ru.AvgHoursToAnswer,
    ru.TotalUpvotes,
    ru.TotalDownvotes,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.TagsAnswered
FROM RankedUsers ru
WHERE ru.YearlyRank <= 10
ORDER BY ru.ActivityYear DESC, ru.YearlyRank ASC;
