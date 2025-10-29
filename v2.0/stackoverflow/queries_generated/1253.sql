-- {"query": "1253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3272} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoritesReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MIN(B.Class) AS BestBadgeClass, -- 1=Gold (lowest number means best class)
        MAX(PH.CreationDate) AS LastActivityDateByUser,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        (U.UpVotes - U.DownVotes) AS NetVotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionPerformance AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.Title,
        Q.Tags,
        COALESCE(Q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        MAX(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS HasBeenFavorited,
        MIN(A.CreationDate) AS FirstAnswerDate,
        MAX(CASE WHEN A.Id = Q.AcceptedAnswerId THEN A.CreationDate ELSE NULL END) AS AcceptedAnswerDate,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 101) THEN PH.Id ELSE NULL END) AS CloseVotesCount, -- Closed post history type
        COUNT(DISTINCT PL.RelatedPostId) AS DuplicateLinksCount,
        (SELECT MIN(CreationDate) FROM Comments WHERE PostId = Q.Id) AS FirstCommentDate,
        LENGTH(Q.Body) AS BodyLength,
        LENGTH(Q.Title) AS TitleLength
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to this question
    LEFT JOIN Votes V ON Q.Id = V.PostId
    LEFT JOIN PostHistory PH ON Q.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId AND PL.LinkTypeId = 3 -- Duplicate links
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.Title, Q.Tags, Q.AcceptedAnswerId, Q.Body
),
AnswerQuality AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        COUNT(DISTINCT C.Id) AS AnswerCommentCount,
        COUNT(DISTINCT PH.Id) AS AnswerEditCount,
        CASE WHEN P.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = A.Id AND V.VoteTypeId = 2) AS AnswerUpvotes,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = A.Id AND V.VoteTypeId = 3) AS AnswerDownvotes
    FROM Posts A
    JOIN Posts P ON A.ParentId = P.Id AND P.PostTypeId = 1 -- Get the parent question
    LEFT JOIN Comments C ON A.Id = C.PostId
    LEFT JOIN PostHistory PH ON A.Id = PH.PostId AND PH.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
    WHERE A.PostTypeId = 2
    GROUP BY A.Id, A.ParentId, A.OwnerUserId, A.CreationDate, A.Score, P.AcceptedAnswerId
)
SELECT
    'HighImpactQuestion' AS RecordType,
    UA.UserId,
    UA.Reputation,
    QP.QuestionId AS PostId,
    QP.Title AS PostTitle,
    QP.QuestionScore AS PostScore,
    QP.ViewCount,
    QP.AnswerCount,
    QP.FavoriteCount,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalBadges,
    (UA.Reputation * 0.1 + QP.QuestionScore * 0.5 + QP.ViewCount * 0.01 + QP.FavoriteCount * 1.0) AS WeightedImpactScore,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM QP.QuestionCreationDate) ORDER BY QP.QuestionScore DESC, QP.ViewCount DESC) AS QuestionScoreRankByYear,
    COALESCE(EXTRACT(EPOCH FROM (QP.AcceptedAnswerDate - QP.QuestionCreationDate)) / 3600, -1) AS TimeToAcceptedAnswerHours, -- -1 if no accepted answer
    SUBSTRING(QP.Title, 1, 50) AS TitleSnippet,
    CASE
        WHEN QP.BodyLength > 1000 AND QP.AnswerCount > 5 THEN 'Verbose & Engaged'
        WHEN QP.QuestionScore >= 50 AND QP.FavoriteCount >= 10 THEN 'Popular & Liked'
        WHEN QP.CloseVotesCount > 0 THEN 'Potentially Problematic'
        ELSE 'Standard'
    END AS QuestionStatusCategory,
    STRING_TO_ARRAY(SUBSTRING(QP.Tags, 2, LENGTH(QP.Tags)-2), '><')[1] AS PrimaryTag,
    (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = UA.UserId) AS OwnerDisplayName, -- Correlated subquery
    (
        SELECT AVG(C.Score)
        FROM Comments C
        WHERE C.PostId = QP.QuestionId AND C.UserId IS NOT NULL
    ) AS AvgCommentScoreOnQuestion,
    LAG(QP.QuestionCreationDate, 1, QP.QuestionCreationDate) OVER (PARTITION BY UA.UserId ORDER BY QP.QuestionCreationDate) AS PreviousQuestionDate,
    LEAD(QP.QuestionCreationDate, 1, QP.QuestionCreationDate) OVER (PARTITION BY UA.UserId ORDER BY QP.QuestionCreationDate) AS NextQuestionDate,
    COALESCE(
        (SELECT MAX(PH_Edit.CreationDate)
         FROM PostHistory PH_Edit
         WHERE PH_Edit.PostId = QP.QuestionId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6)
        ), QP.QuestionCreationDate
    ) AS LatestEditOrCreationDate,
    UA.LastActivityDateByUser,
    CASE WHEN QP.Tags LIKE '%<sql>%' OR QP.Tags LIKE '%<database>%' THEN TRUE ELSE FALSE END AS IsDatabaseRelated,
    NULLIF(QP.UpvotesReceived, 0) AS NonZeroUpvotes, -- Example of NULLIF
    QP.QuestionCreationDate,
    QP.FirstAnswerDate,
    QP.AcceptedAnswerDate
FROM QuestionPerformance QP
JOIN UserActivitySummary UA ON QP.OwnerUserId = UA.UserId
WHERE
    QP.QuestionScore >= 10
    AND QP.ViewCount >= 100
    AND QP.AnswerCount >= 1
    AND (EXTRACT(MONTH FROM QP.QuestionCreationDate) % 2 = 1) -- Only odd months
    AND UA.Reputation > 1000
    AND LENGTH(QP.Title) > 10
    AND QP.Tags IS NOT NULL
    AND COALESCE(UA.BestBadgeClass, 4) <= 2 -- Silver or Gold badges, default to 4 (no badge) if NULL
    AND COALESCE(QP.AcceptedAnswerId, -1) != -1 -- Must have an accepted answer
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_Closed
        WHERE PH_Closed.PostId = QP.QuestionId
          AND PH_Closed.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) -- Closed reasons
          AND PH_Closed.CreationDate > (QP.QuestionCreationDate + INTERVAL '1 month')
    ) -- Not closed more than a month after creation
UNION ALL
SELECT
    'TopAnswerContributor' AS RecordType,
    UA.UserId,
    UA.Reputation,
    AQ.AnswerId AS PostId,
    SUBSTRING(P_Q.Title, 1, 100) AS PostTitle, -- Title of the parent question
    AQ.AnswerScore AS PostScore,
    P_Q.ViewCount, -- View count of the parent question
    P_Q.AnswerCount,
    P_Q.FavoriteCount,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalBadges,
    (UA.Reputation * 0.05 + AQ.AnswerScore * 0.8 + AQ.AnswerUpvotes * 0.2 + (CASE WHEN AQ.IsAcceptedAnswer = 1 THEN 50 ELSE 0 END)) AS WeightedImpactScore,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM AQ.AnswerCreationDate) ORDER BY AQ.AnswerScore DESC, AQ.AnswerUpvotes DESC) AS AnswerScoreRankByYear,
    COALESCE(EXTRACT(EPOCH FROM (AQ.AnswerCreationDate - P_Q.CreationDate)) / 3600, -1) AS TimeToAnswerHours, -- Time from question creation to answer creation
    SUBSTRING(P_Q.Title, 1, 50) AS TitleSnippet,
    CASE
        WHEN AQ.IsAcceptedAnswer = 1 AND AQ.AnswerScore >= 10 THEN 'Accepted & Highly Rated'
        WHEN AQ.AnswerScore >= 20 THEN 'Very High Score'
        WHEN AQ.AnswerCommentCount > 5 THEN 'Highly Discussed Answer'
        ELSE 'Standard Answer'
    END AS AnswerStatusCategory,
    STRING_TO_ARRAY(SUBSTRING(P_Q.Tags, 2, LENGTH(P_Q.Tags)-2), '><')[1] AS PrimaryTag,
    (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = UA.UserId) AS OwnerDisplayName, -- Correlated subquery
    (
        SELECT AVG(C.Score)
        FROM Comments C
        WHERE C.PostId = AQ.AnswerId AND C.UserId IS NOT NULL
    ) AS AvgCommentScoreOnAnswer,
    LAG(AQ.AnswerCreationDate, 1, AQ.AnswerCreationDate) OVER (PARTITION BY UA.UserId ORDER BY AQ.AnswerCreationDate) AS PreviousAnswerDate,
    LEAD(AQ.AnswerCreationDate, 1, AQ.AnswerCreationDate) OVER (PARTITION BY UA.UserId ORDER BY AQ.AnswerCreationDate) AS NextAnswerDate,
    COALESCE(
        (SELECT MAX(PH_Edit.CreationDate)
         FROM PostHistory PH_Edit
         WHERE PH_Edit.PostId = AQ.AnswerId AND PH_Edit.PostHistoryTypeId IN (5, 8)
        ), AQ.AnswerCreationDate
    ) AS LatestEditOrCreationDate,
    UA.LastActivityDateByUser,
    CASE WHEN P_Q.Tags LIKE '%<sql>%' OR P_Q.Tags LIKE '%<database>%' THEN TRUE ELSE FALSE END AS IsDatabaseRelated,
    NULLIF(AQ.AnswerUpvotes, 0) AS NonZeroUpvotes,
    P_Q.CreationDate AS QuestionCreationDate, -- Original Question Creation Date
    AQ.AnswerCreationDate AS FirstAnswerDate, -- Answer Creation Date itself
    NULL AS AcceptedAnswerDate -- Not applicable for an answer record itself
FROM AnswerQuality AQ
JOIN UserActivitySummary UA ON AQ.AnswerOwnerUserId = UA.UserId
JOIN Posts P_Q ON AQ.QuestionId = P_Q.Id -- Get details of the parent question
WHERE
    AQ.AnswerScore >= 5
    AND P_Q.ViewCount >= 50
    AND P_Q.AnswerCount >= 1
    AND (EXTRACT(DAY FROM AQ.AnswerCreationDate) % 3 = 0) -- Only answers posted on days divisible by 3
    AND UA.Reputation > 500
    AND LENGTH(P_Q.Title) > 5
    AND P_Q.Tags IS NOT NULL
    AND AQ.IsAcceptedAnswer = 1 -- Only accepted answers for this part of the UNION
    AND NOT EXISTS (
        SELECT 1
        FROM Badges B
        WHERE B.UserId = UA.UserId
          AND B.Name ILIKE '%suffering%' -- Example badge name
          AND B.Date < AQ.AnswerCreationDate
    ) -- User should not have received a 'suffering' badge before answering
ORDER BY WeightedImpactScore DESC, PostId
LIMIT 1000;
