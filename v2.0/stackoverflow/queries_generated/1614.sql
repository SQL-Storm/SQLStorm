-- {"query": "1614.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2722} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS UserUpvotesGiven,
        U.DownVotes AS UserDownvotesGiven,
        U.Views AS ProfileViews,
        COALESCE(U.Location, 'Unknown') AS UserLocation, -- NULL logic (COALESCE)
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostsScore, -- NULL logic (COALESCE)
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsWithAcceptedAnswer,
        SUM(CASE WHEN P.PostTypeId = 2 AND Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS TotalAnswersAccepted,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        MAX(B.Date) AS LastBadgeEarnedDate,
        ARRAY_AGG(DISTINCT B.Name) FILTER (WHERE B.Name IS NOT NULL) AS UserBadgeNames -- String expression (ARRAY_AGG)
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts Q ON P.ParentId = Q.Id -- Used to check if an answer (P) was accepted for a question (Q)
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.Views, U.Location
),
PostDetailedAnalytics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.Body,
        P.LastEditDate,
        P.ClosedDate,
        COUNT(DISTINCT PH.UserId) AS NumDistinctEditors,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10,12) THEN PH.CreationDate ELSE NULL END) AS LastClosureDeletionEvent,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (5, 8) AND LENGTH(PH.Text) > 500 THEN 1 ELSE 0 END) AS SignificantBodyEditCount, -- String expression (LENGTH)
        EXTRACT(EPOCH FROM (MIN(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) - P.CreationDate)) AS SecondsToFirstEdit -- Complicated calculation (EXTRACT EPOCH)
    FROM
        Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1,2) -- Only Questions and Answers
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.Body, P.LastEditDate, P.ClosedDate
),
TagPerformance AS (
    SELECT
        Tag.Tag AS TagName,
        COUNT(DISTINCT PDA.PostId) AS QuestionsTagged,
        SUM(PDA.ViewCount) AS TotalTagViews,
        AVG(PDA.Score) AS AverageTagQuestionScore,
        AVG(PDA.AnswerCount) AS AverageAnswersPerTaggedQuestion,
        SUM(PDA.FavoriteCount) AS TotalTagFavorites,
        COUNT(DISTINCT T.Id) FILTER (WHERE T.WikiPostId IS NOT NULL) AS HasWikiCount -- Aggregation with FILTER clause
    FROM
        PostDetailedAnalytics PDA
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(PDA.Tags, 2, length(PDA.Tags)-2), '><')) AS Tag(Tag) -- String expression (string_to_array, substring, length)
    LEFT JOIN Tags T ON Tag.Tag = T.TagName
    WHERE PDA.PostTypeId = 1 AND PDA.Tags IS NOT NULL
    GROUP BY
        Tag.Tag
),
QuestionAnswerLinkAnalysis AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerId,
        P.CreationDate AS QuestionCreationDate,
        P.AnswerCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostsCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatePostsCount,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM
        Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId -- Outer join (LEFT JOIN)
    WHERE
        P.PostTypeId = 1
    GROUP BY
        P.Id, P.OwnerUserId, P.CreationDate, P.AnswerCount, P.AcceptedAnswerId
),
-- Set Operator CTEs
HighlyVotedQuestionsWithAcceptedAnswers AS (
    SELECT
        PDA.OwnerUserId AS UserId
    FROM
        PostDetailedAnalytics PDA
    WHERE
        PDA.PostTypeId = 1
        AND PDA.Score > 5
        AND PDA.AnswerCount >= 3
        AND EXISTS (SELECT 1 FROM Posts A WHERE A.ParentId = PDA.PostId AND PDA.AcceptedAnswerId = A.Id) -- Subquery in EXISTS
),
UsersWhoOnlyAnsweredRecently AS (
    SELECT U.Id AS UserId
    FROM Users U
    WHERE U.Id IN (SELECT OwnerUserId FROM Posts WHERE PostTypeId = 2 AND CreationDate >= NOW() - INTERVAL '6 months') -- Has answered recently
    EXCEPT -- Set operator
    SELECT U.Id AS UserId
    FROM Users U
    WHERE U.Id IN (SELECT OwnerUserId FROM Posts WHERE PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '6 months') -- Has NOT asked a question recently
)

SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserLocation,
    UE.TotalPostsOwned,
    UE.TotalPostsScore,
    UE.TotalBadgesEarned,
    UE.TotalQuestionsWithAcceptedAnswer,
    UE.TotalAnswersAccepted,
    STRING_AGG(DISTINCT BadgeName, ', ') AS UserBadges, -- String expression (STRING_AGG)
    TP.TagName AS TopContributingTag,
    TP.AverageTagQuestionScore AS TopTagAvgScore,
    PDA_Q.PostId AS SampleQuestionId,
    PDA_Q.Title AS SampleQuestionTitle,
    PDA_Q.Score AS SampleQuestionScore,
    PDA_Q.ViewCount AS SampleQuestionViewCount,
    PDA_Q.AnswerCount AS SampleQuestionAnswerCount,
    COALESCE(PDA_Q.FavoriteCount, 0) AS SampleQuestionFavoriteCount, -- NULL logic (COALESCE)
    PDA_Q.NumDistinctEditors AS SampleQuestionEditors,
    PDA_Q.ReopenCount AS SampleQuestionReopenCount,
    PDA_Q.SignificantBodyEditCount AS SampleQuestionMajorEdits,
    PDA_Q.SecondsToFirstEdit AS SampleQuestionSecondsToFirstEdit,
    QALA.LinkedPostsCount AS SampleQuestionLinkedPosts,
    QALA.DuplicatePostsCount AS SampleQuestionDuplicatePosts,
    (
        SELECT
            AVG(A.Score)
        FROM
            Posts A
        INNER JOIN Users AU ON A.OwnerUserId = AU.Id
        WHERE
            A.PostTypeId = 2
            AND A.ParentId = PDA_Q.PostId -- Correlated part of subquery
            AND AU.Reputation > 1000
            AND A.CreationDate > PDA_Q.PostCreationDate -- Correlated subquery with complicated predicate
    ) AS AvgScoreOfHighReputationAnswers,
    CASE
        WHEN UE.Reputation > 5000 AND UE.TotalQuestionsWithAcceptedAnswer > 5 THEN 'Veteran Contributor'
        WHEN UE.TotalBadgesEarned >= 10 AND UE.TotalPostsScore > 100 THEN 'Active Community Member'
        WHEN UE.TotalCommentsMade > 50 AND UE.TotalPostsOwned = 0 THEN 'Dedicated Commenter'
        ELSE 'Casual User'
    END AS UserCategory, -- Complicated Predicate/Expression/Calculation (CASE statement)
    RANK() OVER (ORDER BY UE.Reputation DESC, UE.TotalPostsScore DESC, UE.TotalAnswersAccepted DESC) AS GlobalUserRank, -- Window function (RANK)
    AVG(UE.TotalPostsScore) OVER (PARTITION BY UE.UserLocation) AS AvgPostsScoreInLocation, -- Window function (AVG with PARTITION BY)
    LAG(UE.LastPostActivityDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY UE.LastPostActivityDate) AS PrevPostActivityDate, -- Window function (LAG with default value)
    EXISTS (SELECT 1 FROM HighlyVotedQuestionsWithAcceptedAnswers HVQ WHERE HVQ.UserId = UE.UserId) AS HasHighlyRatedQuestions,
    EXISTS (SELECT 1 FROM UsersWhoOnlyAnsweredRecently UWAR WHERE UWAR.UserId = UE.UserId) AS IsRecentAnswerOnlyUser
FROM
    UserEngagement UE
LEFT JOIN LATERAL ( -- Outer join (LEFT JOIN) with LATERAL subquery
    SELECT PDA.*
    FROM PostDetailedAnalytics PDA
    WHERE PDA.OwnerUserId = UE.UserId AND PDA.PostTypeId = 1
    ORDER BY PDA.CreationDate DESC
    LIMIT 1
) AS PDA_Q ON TRUE -- Gets a sample question for each user
LEFT JOIN LATERAL ( -- Outer join (LEFT JOIN) with LATERAL subquery
    SELECT Tag.TagName
    FROM PostDetailedAnalytics PDA_Tag
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(PDA_Tag.Tags, 2, length(PDA_Tag.Tags)-2), '><')) AS Tag(TagName)
    WHERE PDA_Tag.OwnerUserId = UE.UserId AND PDA_Tag.PostTypeId = 1 AND PDA_Tag.Tags IS NOT NULL
    GROUP BY Tag.TagName
    ORDER BY COUNT(PDA_Tag.PostId) DESC, SUM(PDA_Tag.ViewCount) DESC
    LIMIT 1
) AS TopTag ON TRUE -- Gets the most frequently used tag for questions for each user
LEFT JOIN TagPerformance TP ON TopTag.TagName = TP.TagName -- Outer join (LEFT JOIN)
LEFT JOIN QuestionAnswerLinkAnalysis QALA ON PDA_Q.PostId = QALA.QuestionId -- Outer join (LEFT JOIN)
WHERE
    UE.Reputation > 500
    AND UE.TotalPostsOwned > 0
    AND UE.TotalBadgesEarned > 0
    AND (PDA_Q.Body LIKE '%sql%' OR PDA_Q.Body LIKE '%database%') -- String expression (LIKE)
    AND UE.LastPostActivityDate IS NOT NULL AND UE.LastPostActivityDate >= NOW() - INTERVAL '2 years' -- NULL logic (IS NOT NULL)
ORDER BY
    GlobalUserRank ASC, UE.UserId
LIMIT 1000;
