WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(P.Score) AS TotalPostScoreReceived,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(P.FavoriteCount) AS TotalPostFavorites,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MIN(P.CreationDate) AS FirstPostCreationDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostInteractionSummary AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.ClosedDate,
        COUNT(DISTINCT V.Id) AS TotalVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS ClosedEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenedEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.Id END) AS DeletedEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 35 THEN PH.Id ELSE NULL END) AS MigratedAwayEvents
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate
),
RankedQuestionOwners AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalPostsOwned,
        UE.QuestionsOwned,
        SUM(PIS.PostScore) AS TotalQuestionScore,
        SUM(PIS.ViewCount) AS TotalQuestionViewCount,
        SUM(PIS.AnswerCount) AS TotalQuestionAnswerCount,
        SUM(PIS.EditCount) AS TotalQuestionEditCount,
        SUM(PIS.ClosedEvents) AS TotalQuestionClosedEvents,
        SUM(PIS.UpVotesReceived) AS TotalQuestionUpVotesReceived,
        ROW_NUMBER() OVER (ORDER BY UE.Reputation DESC, SUM(PIS.ViewCount) DESC, SUM(PIS.AnswerCount) DESC) AS RepAndViewRank,
        DENSE_RANK() OVER (PARTITION BY UE.DisplayName ORDER BY SUM(PIS.EditCount) DESC, SUM(PIS.ClosedEvents) DESC) AS EditAndClosedRank
    FROM
        UserEngagement UE
    JOIN
        PostInteractionSummary PIS ON UE.UserId = PIS.OwnerUserId
    WHERE
        PIS.PostTypeId = 1
        AND PIS.ViewCount > 500
        AND UE.QuestionsOwned > 0
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.TotalPostsOwned, UE.QuestionsOwned
    HAVING
        SUM(PIS.EditCount) > 0 OR SUM(PIS.ClosedEvents) > 0
),
HighlyVotedAnswers AS (
    SELECT
        P.OwnerUserId AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) AS TotalAnswers,
        SUM(CASE WHEN P_Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS AcceptedAnswers,
        SUM(CASE WHEN P_Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(P.Id), 0) AS AcceptanceRate,
        SUM(P.Score) AS TotalAnswerScore,
        MAX(P.Score) AS MaxAnswerScore,
        RANK() OVER (ORDER BY SUM(P.Score) DESC, SUM(CASE WHEN P_Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(P.Id), 0) DESC) AS AnswerScoreRank
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Posts P_Q ON P.ParentId = P_Q.Id AND P_Q.PostTypeId = 1
    WHERE
        P.PostTypeId = 2
        AND P.Score >= 10
    GROUP BY
        P.OwnerUserId, U.DisplayName, U.Reputation
    HAVING
        COUNT(P.Id) >= 5
        AND SUM(CASE WHEN P_Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(P.Id), 0) > 0.1
)
SELECT
    'QuestionOwner' AS ContributionType,
    R.UserId,
    R.DisplayName,
    R.Reputation,
    R.QuestionsOwned AS PrimaryCount,
    R.TotalQuestionScore AS PrimaryScore,
    R.TotalQuestionViewCount AS SecondaryCount,
    R.TotalQuestionEditCount AS TertiaryCount,
    R.TotalQuestionClosedEvents AS QuaternaryCount,
    NULL AS AcceptanceRate,
    NULL AS MaxAnswerScore,
    'https://stackoverflow.com/users/' || R.UserId AS UserProfileLink,
    UPPER(SUBSTRING(COALESCE(U.Location, 'Unknown Location') FROM 1 FOR 10)) AS UserLocationPrefix,
    CASE
        WHEN R.TotalQuestionClosedEvents > 0 AND R.TotalQuestionEditCount > 5 THEN 'Highly Discussed & Edited'
        WHEN R.TotalQuestionClosedEvents > 0 THEN 'Subject to Closure'
        WHEN R.TotalQuestionEditCount > 5 THEN 'Frequently Refined'
        ELSE 'Standard Contributor'
    END AS QuestionStatusCategory,
    (SELECT COUNT(DISTINCT PL.RelatedPostId)
     FROM PostLinks PL
     WHERE PL.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = R.UserId AND PostTypeId = 1)
       AND PL.LinkTypeId = 3) AS DuplicatesLinkedFromOwnedQuestions,
    AVG(P_TopQ.Score) AS AvgScoreOfTopQuestions,
    LAG(R.Reputation, 1, 0) OVER (ORDER BY R.RepAndViewRank) AS PreviousRankedUserReputation,
    U.CreationDate AS UserCreationDate,
    (TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate) AS AccountAge
FROM
    RankedQuestionOwners R
JOIN
    Users U ON R.UserId = U.Id
LEFT JOIN
    Posts P_TopQ ON U.Id = P_TopQ.OwnerUserId AND P_TopQ.PostTypeId = 1 AND P_TopQ.Score > 0
WHERE
    R.RepAndViewRank <= 100
    AND U.DisplayName IS NOT NULL
    AND (U.AboutMe IS NULL OR U.AboutMe LIKE '%software%' OR U.AboutMe LIKE '%developer%')
    AND U.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Location = U.Location AND Reputation IS NOT NULL)
    AND EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = R.UserId AND LOWER(B.Name) LIKE '%gold%' AND B.TagBased = TRUE)
GROUP BY
    R.UserId, R.DisplayName, R.Reputation, R.QuestionsOwned, R.TotalQuestionScore, R.TotalQuestionViewCount,
    R.TotalQuestionEditCount, R.TotalQuestionClosedEvents, R.RepAndViewRank, U.Location, U.CreationDate, U.AboutMe, P_TopQ.OwnerUserId
UNION ALL
SELECT
    'Answerer' AS ContributionType,
    H.UserId,
    H.DisplayName,
    H.Reputation,
    H.TotalAnswers AS PrimaryCount,
    H.TotalAnswerScore AS PrimaryScore,
    NULL AS SecondaryCount,
    NULL AS TertiaryCount,
    NULL AS QuaternaryCount,
    H.AcceptanceRate,
    H.MaxAnswerScore,
    'https://stackoverflow.com/users/' || H.UserId AS UserProfileLink,
    UPPER(SUBSTRING(COALESCE(U.Location, 'Unknown Location') FROM 1 FOR 10)) AS UserLocationPrefix,
    CASE
        WHEN H.AcceptanceRate > 0.5 AND H.TotalAnswers > 100 THEN 'Elite Answerer'
        WHEN H.AcceptanceRate > 0.2 THEN 'Good Acceptance'
        ELSE 'Developing Answerer'
    END AS AnswerStatusCategory,
    (SELECT COUNT(DISTINCT Q.Id)
     FROM Posts Q
     JOIN Posts A ON Q.AcceptedAnswerId = A.Id
     WHERE A.OwnerUserId = H.UserId AND Q.PostTypeId = 1 AND A.PostTypeId = 2) AS QuestionsAcceptedMyAnswers,
    NULL AS AvgScoreOfTopQuestions,
    LAG(H.Reputation, 1, 0) OVER (ORDER BY H.AnswerScoreRank) AS PreviousRankedUserReputation,
    U.CreationDate AS UserCreationDate,
    (TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate) AS AccountAge
FROM
    HighlyVotedAnswers H
JOIN
    Users U ON H.UserId = U.Id
WHERE
    H.AnswerScoreRank <= 50
    AND H.Reputation > 10000
    AND (U.AboutMe IS NOT NULL AND (U.AboutMe LIKE '%developer%' OR U.AboutMe LIKE '%engineer%'))
    AND NOT EXISTS (SELECT 1 FROM Votes V WHERE V.UserId = H.UserId AND V.VoteTypeId = 4 AND V.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'))
ORDER BY
    ContributionType DESC, Reputation DESC, PrimaryScore DESC
LIMIT 200;