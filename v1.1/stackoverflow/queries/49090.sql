WITH UserQuestionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT q.Id) AS TotalQuestionsAsked,
        SUM(q.ViewCount) AS TotalQuestionViews,
        SUM(COALESCE(q.FavoriteCount, 0)) AS TotalQuestionFavorites,
        MAX(q.CreationDate) AS LastQuestionActivityDate
    FROM Users u
    INNER JOIN Posts q ON u.Id = q.OwnerUserId
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate >= (DATE '2024-10-01' - INTERVAL '5' YEAR)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(DISTINCT q.Id) >= 10
        AND u.Reputation >= 1000
),
QuestionAnswerPerformance AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        AVG(CAST(a.Score AS DOUBLE PRECISION)) AS AverageAnswerScore,
        COUNT(a.Id) AS NumberOfAnswers,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE
        q.PostTypeId = 1
        AND a.PostTypeId = 2
        AND a.CreationDate >= (DATE '2024-10-01' - INTERVAL '5' YEAR)
    GROUP BY
        q.Id, q.OwnerUserId
    HAVING
        AVG(CAST(a.Score AS DOUBLE PRECISION)) >= 7.0
        AND COUNT(a.Id) >= 3
),
QuestionTagPopularity AS (
    SELECT
        q.Id AS QuestionId,
        SUM(t.Count) AS TotalQuestionTagPopularity,
        COUNT(DISTINCT t.Id) AS DistinctTagCount
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT tag_name
        FROM (
            SELECT regexp_split_to_table(SUBSTRING(q.Tags FROM 2 FOR (LENGTH(q.Tags) - 2)), '><') AS tag_name
        ) s
    ) tag_names
    INNER JOIN Tags t ON t.TagName = tag_names.tag_name
    WHERE
        q.PostTypeId = 1
        AND q.Tags IS NOT NULL
        AND LENGTH(q.Tags) > 2
    GROUP BY
        q.Id
    HAVING
        SUM(t.Count) > 5000
),
UserEngagementMetrics AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadgesReceived,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '5' YEAR)
    GROUP BY
        u.Id
)
SELECT
    uqs.UserId,
    uqs.DisplayName,
    uqs.Reputation,
    uqs.TotalQuestionsAsked,
    uqs.TotalQuestionViews,
    uqs.TotalQuestionFavorites,
    uqs.LastQuestionActivityDate,
    AVG(qap.AverageAnswerScore) AS AverageOfAnswerScoresAcrossQuestions,
    AVG(qap.NumberOfAnswers) AS AverageAnswersPerQuestion,
    SUM(qtp.TotalQuestionTagPopularity) AS CumulativeTagPopularityForUserQuestions,
    COUNT(DISTINCT qap.QuestionId) AS QuestionsWithHighPerformingAnswers,
    COALESCE(uem.TotalBadgesReceived, 0) AS TotalBadgesReceived,
    COALESCE(uem.GoldBadges, 0) AS GoldBadges,
    COALESCE(uem.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(uem.TotalUpvotesGiven, 0) AS TotalUpvotesGiven,
    COALESCE(uem.TotalDownvotesGiven, 0) AS TotalDownvotesGiven,
    (
        uqs.Reputation * 0.05 +
        uqs.TotalQuestionsAsked * 0.5 +
        uqs.TotalQuestionViews * 0.0005 +
        uqs.TotalQuestionFavorites * 0.2 +
        AVG(qap.AverageAnswerScore) * 1.5 +
        SUM(qtp.TotalQuestionTagPopularity) * 0.00001 +
        COALESCE(uem.TotalBadgesReceived, 0) * 0.1 +
        COALESCE(uem.GoldBadges, 0) * 1.0 +
        COALESCE(uem.TotalCommentsMade, 0) * 0.05 +
        COALESCE(uem.TotalUpvotesGiven, 0) * 0.01
    ) AS UserCompositeScore,
    RANK() OVER (
        ORDER BY
            (uqs.Reputation * 0.05 + AVG(qap.AverageAnswerScore) * 1.5 + SUM(qtp.TotalQuestionTagPopularity) * 0.00001 + COALESCE(uem.GoldBadges, 0) * 1.0) DESC,
            uqs.LastQuestionActivityDate DESC
    ) AS UserRankByImpact
FROM UserQuestionStats uqs
INNER JOIN QuestionAnswerPerformance qap ON uqs.UserId = qap.OwnerUserId
INNER JOIN QuestionTagPopularity qtp ON qap.QuestionId = qtp.QuestionId
LEFT JOIN UserEngagementMetrics uem ON uqs.UserId = uem.UserId
GROUP BY
    uqs.UserId, uqs.DisplayName, uqs.Reputation, uqs.UserCreationDate,
    uqs.TotalQuestionsAsked, uqs.TotalQuestionViews, uqs.TotalQuestionFavorites,
    uqs.LastQuestionActivityDate, uem.TotalBadgesReceived, uem.GoldBadges,
    uem.TotalCommentsMade, uem.TotalUpvotesGiven, uem.TotalDownvotesGiven
HAVING
    COUNT(DISTINCT qap.QuestionId) >= 5
    AND AVG(qap.AverageAnswerScore) >= 8.0
ORDER BY
    UserCompositeScore DESC, UserRankByImpact ASC
LIMIT 50;