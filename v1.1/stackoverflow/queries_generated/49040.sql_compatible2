WITH UserAnswerTagPerformance AS (
    SELECT
        P.OwnerUserId AS UserId,
        LOWER(TRIM(t.tag)) AS TagName,
        COUNT(P.Id) AS TotalAnswers,
        SUM(P.Score) AS TotalAnswerScore,
        COUNT(CASE WHEN P.Id = QP.AcceptedAnswerId THEN 1 ELSE NULL END) AS AcceptedAnswersCount,
        MAX(P.CreationDate) AS LastAnswerDate,
        AVG(P.Score) AS AvgAnswerScore
    FROM Posts AS P
    JOIN Posts AS QP ON P.ParentId = QP.Id
    CROSS JOIN LATERAL (
        -- split tags like <tag1><tag2> into rows using standard functions
        SELECT UNNEST(string_to_array(SUBSTRING(QP.Tags FROM 2 FOR (LENGTH(QP.Tags) - 2)), '><')) AS tag
    ) t
    WHERE
        P.PostTypeId = 2
        AND P.OwnerUserId IS NOT NULL
        AND QP.PostTypeId = 1
        AND P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years'
        AND P.Score > 0
        AND QP.Tags IS NOT NULL
        AND LENGTH(QP.Tags) > 2
    GROUP BY
        P.OwnerUserId,
        LOWER(TRIM(t.tag))
),
UserOverallActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes AS TotalUpvotesGiven,
        U.DownVotes AS TotalDownvotesGiven,
        U.Views AS ProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id ELSE NULL END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id ELSE NULL END) AS TotalAnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceived,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id ELSE NULL END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id ELSE NULL END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id ELSE NULL END) AS BronzeBadges,
        MAX(U.LastAccessDate) AS LastSeen
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views
),
RankedTagPerformance AS (
    SELECT
        UserId,
        TagName,
        TotalAnswers,
        TotalAnswerScore,
        AcceptedAnswersCount,
        AvgAnswerScore,
        RANK() OVER (PARTITION BY UserId ORDER BY TotalAnswerScore DESC, AcceptedAnswersCount DESC, TotalAnswers DESC) AS TagScoreRank,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TotalAnswerScore DESC, AcceptedAnswersCount DESC, TotalAnswers DESC) AS TagRankNum
    FROM UserAnswerTagPerformance
    WHERE TotalAnswers >= 5
),
TopTagsPerUser AS (
    SELECT
        UserId,
        TagName AS TopTagName,
        TotalAnswers AS TopTagAnswers,
        TotalAnswerScore AS TopTagScore,
        AcceptedAnswersCount AS TopTagAcceptedAnswers,
        AvgAnswerScore AS TopTagAvgScore
    FROM RankedTagPerformance
    WHERE TagRankNum = 1
)
SELECT
    UOA.DisplayName,
    UOA.Reputation,
    UOA.TotalPostsCreated,
    UOA.TotalAnswersCreated,
    UOA.TotalUpvotesReceived,
    UOA.TotalFavoritesReceived,
    TTU.TopTagName,
    TTU.TopTagScore,
    TTU.TopTagAcceptedAnswers,
    TTU.TopTagAvgScore,
    UOA.GoldBadges,
    UOA.SilverBadges,
    UOA.BronzeBadges,
    UOA.LastSeen,
    (
        UOA.Reputation * 0.5 +
        UOA.TotalUpvotesReceived * 0.3 +
        UOA.TotalFavoritesReceived * 0.1 +
        TTU.TopTagScore * 0.05 +
        TTU.TopTagAcceptedAnswers * 0.05 +
        (UOA.GoldBadges * 100 + UOA.SilverBadges * 10 + UOA.BronzeBadges * 1) * 0.01
    ) AS CompositePerformanceScore
FROM UserOverallActivity AS UOA
JOIN TopTagsPerUser AS TTU ON UOA.UserId = TTU.UserId
WHERE
    UOA.Reputation >= 1000
    AND UOA.TotalAnswersCreated >= 10
    AND UOA.LastSeen >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
ORDER BY CompositePerformanceScore DESC, UOA.Reputation DESC
LIMIT 100;