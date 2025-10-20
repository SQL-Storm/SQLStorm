-- {"query": "49066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1734} 

WITH QuestionMetadata AS (
    -- Selects relevant questions within the last two years that have accepted answers and specific tags.
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.AcceptedAnswerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.FavoriteCount,
        Q.CommentCount,
        Q.LastActivityDate AS QuestionLastActivityDate
    FROM Posts AS Q
    WHERE
        Q.PostTypeId = 1
        AND Q.AcceptedAnswerId IS NOT NULL
        AND (Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<postgresql>%' OR Q.Tags LIKE '%<database>%')
        AND Q.CreationDate >= (CURRENT_DATE - INTERVAL '2 year')
),
AcceptedAnswerDetails AS (
    -- Retrieves details of the accepted answers for the questions identified above.
    SELECT
        QM.QuestionId,
        QM.QuestionOwnerId,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        A.CommentCount AS AnswerCommentCount
    FROM QuestionMetadata AS QM
    JOIN Posts AS A ON QM.AcceptedAnswerId = A.Id
),
UserAggregatedStats AS (
    -- Aggregates various statistics for each user based on their questions and accepted answers.
    SELECT
        QO.QuestionOwnerId AS UserId,
        COUNT(DISTINCT QO.QuestionId) AS TotalQuestionsAsked,
        SUM(AAD.AnswerScore) AS TotalAcceptedAnswerScore,
        AVG(AAD.AnswerScore) AS AverageAcceptedAnswerScore,
        MAX(QO.QuestionCreationDate) AS LastQuestionPostDate,
        SUM(QO.ViewCount) AS TotalQuestionViewCount,
        SUM(QO.QuestionScore) AS TotalQuestionScore,
        SUM(QO.FavoriteCount) AS TotalQuestionFavoriteCount,
        SUM(QO.CommentCount) AS TotalQuestionCommentCount,
        COUNT(DISTINCT AAD.AnswerOwnerId) AS UniqueAnswerersForQuestions,
        SUM(AAD.AnswerCommentCount) AS TotalAcceptedAnswerCommentCount
    FROM QuestionMetadata AS QO
    JOIN AcceptedAnswerDetails AS AAD ON QO.QuestionId = AAD.QuestionId
    GROUP BY QO.QuestionOwnerId
),
UserBadgeSummary AS (
    -- Counts the number of gold, silver, and bronze badges for each user.
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserPostHistorySummary AS (
    -- Summarizes post history events (edits, closes, reopens) for each user.
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 END) AS PostEditEvents, -- Edit/Rollback Title, Body, Tags
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS PostClosedEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS PostReopenedEvents
    FROM PostHistory AS PH
    WHERE PH.UserId IS NOT NULL -- Exclude community/anonymous history
    GROUP BY PH.UserId
),
UserCommentActivity AS (
    -- Aggregates comment scores and counts for each user.
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Comments AS C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS UserTotalUpVotes,
    U.DownVotes AS UserTotalDownVotes,
    U.Views AS UserProfileViews,
    U.CreationDate AS UserAccountCreationDate,
    U.LastAccessDate,
    UAS.TotalQuestionsAsked,
    UAS.TotalAcceptedAnswerScore,
    UAS.AverageAcceptedAnswerScore,
    UAS.LastQuestionPostDate,
    UAS.TotalQuestionViewCount,
    UAS.TotalQuestionScore,
    UAS.TotalQuestionFavoriteCount,
    UAS.TotalQuestionCommentCount,
    UAS.UniqueAnswerersForQuestions,
    UAS.TotalAcceptedAnswerCommentCount,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UPHS.PostEditEvents, 0) AS UserPostEditEvents,
    COALESCE(UPHS.PostClosedEvents, 0) AS UserPostClosedEvents,
    COALESCE(UPHS.PostReopenedEvents, 0) AS UserPostReopenedEvents,
    COALESCE(UCA.TotalCommentsMade, 0) AS UserTotalCommentsMade,
    COALESCE(UCA.TotalCommentScore, 0) AS UserTotalCommentScore,
    UCA.LastCommentDate,
    -- Calculate a weighted performance score for ranking
    (
        UAS.AverageAcceptedAnswerScore * 10.0 +
        (U.Reputation / 1000.0) +
        (COALESCE(UBS.GoldBadges, 0) * 50.0) +
        (COALESCE(UBS.SilverBadges, 0) * 10.0) +
        (COALESCE(UBS.BronzeBadges, 0) * 1.0) +
        (UAS.TotalQuestionScore / 10.0) +
        (UAS.TotalQuestionFavoriteCount * 5.0) +
        (COALESCE(UCA.TotalCommentScore, 0) / 2.0)
    ) AS WeightedPerformanceScore,
    RANK() OVER (
        ORDER BY
            U.Reputation DESC,
            UAS.AverageAcceptedAnswerScore DESC,
            COALESCE(UBS.GoldBadges, 0) DESC,
            UAS.TotalQuestionScore DESC,
            U.LastAccessDate DESC
    ) AS OverallRank
FROM Users AS U
INNER JOIN UserAggregatedStats AS UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgeSummary AS UBS ON U.Id = UBS.UserId
LEFT JOIN UserPostHistorySummary AS UPHS ON U.Id = UPHS.UserId
LEFT JOIN UserCommentActivity AS UCA ON U.Id = UCA.UserId
WHERE
    U.Reputation > 5000 -- Focus on more established users
    AND U.LastAccessDate >= (CURRENT_DATE - INTERVAL '1 year') -- Only consider users active in the last year
ORDER BY
    WeightedPerformanceScore DESC,
    U.Reputation DESC
LIMIT 200;
