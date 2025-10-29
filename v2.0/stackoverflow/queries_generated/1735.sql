-- {"query": "1735.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2483} 

WITH AggregatedUserData AS (
    -- Summarizes user activity, reputation, and various post/comment counts.
    -- Includes window functions for ranking and cumulative sums.
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.WebsiteUrl,
        U.Views AS UserViews,
        U.UpVotes,
        U.DownVotes,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionsAsked,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswersGiven,
        COUNT(C.Id) AS TotalCommentsMade,
        AVG(P.Score) FILTER (WHERE P.Score IS NOT NULL) AS AvgPostScore,
        SUM(P.ViewCount) FILTER (WHERE P.PostTypeId = 1 AND P.ViewCount IS NOT NULL) AS TotalQuestionViews,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.CreationDate) AS LastPostDate,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank,
        SUM(U.UpVotes) OVER (ORDER BY U.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpVotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Views, U.UpVotes, U.DownVotes
),
FlattenedPostTags AS (
    -- Deconstructs the 'Tags' string column into individual tag rows for questions.
    SELECT
        P.Id AS PostId,
        TRIM(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS TagName,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
TagAggregates AS (
    -- Aggregates statistics per tag, including a popularity rank using a window function.
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TotalQuestionsWithTag,
        AVG(PostScore) AS AvgQuestionScoreForTag,
        SUM(PostViewCount) AS TotalViewsForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT PostId) DESC, SUM(PostViewCount) DESC) AS TagPopularityRank
    FROM FlattenedPostTags
    GROUP BY TagName
    HAVING COUNT(DISTINCT PostId) > 50
),
PostDetailedMetrics AS (
    -- Computes comprehensive metrics for each question post, including subqueries and window functions.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.Tags,
        COALESCE(Q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        A.Score AS AcceptedAnswerScore,
        A.CreationDate AS AcceptedAnswerCreationDate,
        -- Scalar subquery: Average score of all answers for this question
        (
            SELECT AVG(SubA.Score)
            FROM Posts SubA
            WHERE SubA.ParentId = Q.Id AND SubA.PostTypeId = 2 AND SubA.Score IS NOT NULL
        ) AS AvgOfAllAnswerScores,
        -- Scalar subquery: Count of distinct users who commented on this question
        (
            SELECT COUNT(DISTINCT C.UserId)
            FROM Comments C
            WHERE C.PostId = Q.Id AND C.UserId IS NOT NULL
        ) AS DistinctCommentersCount,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsMarkedAsDuplicate,
        MAX(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinksToOtherPosts,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM Q.CreationDate), EXTRACT(MONTH FROM Q.CreationDate) ORDER BY Q.Score DESC, Q.ViewCount DESC) AS MonthlyQuestionRank,
        Q.Score - LAG(Q.Score, 1, 0) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS ScoreDifferenceFromPreviousQuestionByOwner
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId OR Q.Id = PL.RelatedPostId
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.Title, Q.Body, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.Tags, Q.AcceptedAnswerId, A.Score, A.CreationDate
),
PostHistorySummary AS (
    -- Aggregates post history details, including a correlated subquery for the last editor.
    SELECT
        PH.PostId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 24)) AS TotalEditRevisions,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventsCount,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS LastContentEditDate,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 10) AS FirstClosedDate,
        (
            SELECT U_Editor.DisplayName
            FROM PostHistory PH_sub
            JOIN Users U_Editor ON PH_sub.UserId = U_Editor.Id
            WHERE PH_sub.PostId = PH.PostId AND PH_sub.PostHistoryTypeId = 5
            ORDER BY PH_sub.CreationDate DESC
            LIMIT 1
        ) AS LastBodyEditorDisplayName
    FROM PostHistory PH
    GROUP BY PH.PostId
)
SELECT
    AU.UserId,
    AU.DisplayName AS UserDisplayName,
    AU.Reputation,
    AU.ReputationRank,
    AU.UserCreationDate,
    AU.TotalQuestionsAsked,
    AU.TotalAnswersGiven,
    AU.TotalCommentsMade,
    AU.AvgPostScore,
    AU.TotalQuestionViews,
    COALESCE(AU.WebsiteUrl, 'No Website Provided') AS UserWebsiteStatus,
    PDM.QuestionId,
    PDM.QuestionTitle,
    PDM.QuestionScore,
    PDM.QuestionViewCount,
    PDM.QuestionAnswerCount,
    PDM.QuestionFavoriteCount,
    PDM.AcceptedAnswerId,
    PDM.AcceptedAnswerScore,
    PDM.AvgOfAllAnswerScores,
    PDM.DistinctCommentersCount,
    PDM.MonthlyQuestionRank,
    PDM.ScoreDifferenceFromPreviousQuestionByOwner,
    PHS.TotalEditRevisions,
    PHS.CloseEventsCount,
    PHS.ReopenEventsCount,
    PHS.LastContentEditDate,
    PHS.FirstClosedDate,
    PHS.LastBodyEditorDisplayName,
    TA.TagName AS DominantTagName,
    TA.TotalQuestionsWithTag AS DominantTagQuestionsCount,
    TA.AvgQuestionScoreForTag AS DominantTagAvgScore,
    (AU.TotalQuestionsAsked * 5 + AU.TotalAnswersGiven * 3 + AU.TotalCommentsMade * 1 + AU.UpVotes / 10 - AU.DownVotes / 5) AS UserEngagementScore,
    PDM.QuestionTitle LIKE '%performance%' OR PDM.QuestionTitle LIKE '%optimization%' AS IsPerformanceRelatedQuestion,
    CASE
        WHEN AU.Reputation > 20000 AND AU.TotalQuestionsAsked > 100 AND AU.TotalAnswersGiven > 200 THEN 'Veteran & Highly Active'
        WHEN AU.Reputation > 5000 AND (AU.TotalQuestionsAsked > 50 OR AU.TotalAnswersGiven > 100) THEN 'Established Contributor'
        WHEN AU.Reputation > 500 OR AU.TotalQuestionsAsked > 10 OR AU.TotalAnswersGiven > 20 THEN 'Active Member'
        ELSE 'Casual User'
    END AS UserCategory,
    PDM.Tags LIKE '%<sql>%' AS HasSqlTag,
    EXTRACT(DAY FROM (NOW() - AU.LastAccessDate)) AS DaysSinceLastAccess,
    PDM.QuestionBody LIKE '%error%' OR PDM.QuestionBody LIKE '%exception%' OR PDM.QuestionBody LIKE '%debug%' AS QuestionNeedsDebuggingHelp,
    (SELECT AVG(SubU.Reputation) FROM Users SubU ORDER BY SubU.Reputation DESC LIMIT 100) AS AvgReputationTop100Users
FROM AggregatedUserData AU
LEFT JOIN PostDetailedMetrics PDM ON AU.UserId = PDM.OwnerUserId
LEFT JOIN PostHistorySummary PHS ON PDM.QuestionId = PHS.PostId
LEFT JOIN FlattenedPostTags FPT ON PDM.QuestionId = FPT.PostId
LEFT JOIN TagAggregates TA ON FPT.TagName = TA.TagName AND TA.TagPopularityRank <= 100
WHERE
    AU.LastAccessDate >= '2023-01-01'
    AND AU.Reputation > 100
    AND PDM.QuestionId IS NOT NULL
    AND PDM.MonthlyQuestionRank <= 50
    AND PDM.AvgOfAllAnswerScores > 5
    AND PDM.QuestionViewCount > 1000
    AND PHS.CloseEventsCount = 0
    AND NOT EXISTS (
        SELECT 1
        FROM Badges B
        WHERE B.UserId = AU.UserId AND B.Name = 'Disciplined' AND B.Class = 1
    )
    AND (PDM.IsMarkedAsDuplicate = 0 OR PDM.LinksToOtherPosts = 1)
    AND PDM.QuestionTitle IS NOT NULL
ORDER BY
    AU.Reputation DESC,
    PDM.QuestionScore DESC,
    AU.LastAccessDate DESC
LIMIT 5000;
