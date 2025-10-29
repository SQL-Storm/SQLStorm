-- {"query": "1700.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2845} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarizes user activity, reputation, and badge counts.
    -- Includes a non-correlated subquery for badge count and favorite votes.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        MAX(P.CreationDate) AS LatestPostDate,
        U.CreationDate AS UserCreationDate,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges, -- Non-correlated subquery
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 5) AS FavoriteVotesGiven
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate
),
AnswerAggregates AS (
    -- CTE 2: Pre-aggregates answer scores and counts for each question.
    SELECT
        A.ParentId AS QuestionId,
        AVG(A.Score) AS AvgAnswerScore,
        SUM(A.Score) AS TotalAnswerScore,
        COUNT(A.Id) AS ActualAnswerCount
    FROM
        Posts A
    WHERE
        A.PostTypeId = 2
    GROUP BY
        A.ParentId
),
QuestionHistoryAggregates AS (
    -- CTE 3: Aggregates post history details for questions, including editor counts and close reasons.
    -- Uses MAX() FILTER (WHERE ...) for conditional aggregation for close reason name.
    SELECT
        PH.PostId AS QuestionId,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        MIN(PH.CreationDate) AS FirstHistoryEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosedFlag,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopenedFlag,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditHistoryCount,
        MAX(CR.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS CloseReasonName
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id = CAST(PH.Comment AS smallint)
    GROUP BY
        PH.PostId
),
QuestionEngagementMetrics AS (
    -- CTE 4: Combines base question data with aggregated answer and history metrics.
    -- Includes NTILE and RANK window functions.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount AS DeclaredAnswerCount,
        Q.CommentCount,
        Q.FavoriteCount,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(Q.Tags, 2, LENGTH(Q.Tags) - 2), '><') AS TagArray, -- String expression for tag parsing
        AA.AvgAnswerScore,
        AA.TotalAnswerScore,
        COALESCE(AA.ActualAnswerCount, 0) AS ActualAnswerCount, -- NULL logic with COALESCE
        QHA.UniqueEditors,
        QHA.LastHistoryEditDate,
        QHA.FirstHistoryEditDate,
        QHA.WasClosedFlag,
        QHA.WasReopenedFlag,
        QHA.EditHistoryCount,
        QHA.CloseReasonName,
        NTILE(4) OVER (ORDER BY Q.ViewCount DESC) AS ViewCountQuartile, -- Window function
        RANK() OVER (ORDER BY Q.FavoriteCount DESC NULLS LAST, Q.CreationDate ASC) AS FavoriteRank -- Window function with NULLS LAST
    FROM
        Posts Q
    LEFT JOIN
        AnswerAggregates AA ON Q.Id = AA.QuestionId
    LEFT JOIN
        QuestionHistoryAggregates QHA ON Q.Id = QHA.QuestionId
    WHERE
        Q.PostTypeId = 1
),
ExpertAnswerers AS (
    -- CTE 5: Identifies potential "expert" answerers based on reputation, answers, and score.
    -- Uses a CASE statement for user tier classification.
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswererUserId,
        A.Score AS AnswerScore,
        UAS.Reputation AS AnswererReputation,
        UAS.GoldBadges AS AnswererGoldBadges,
        CASE
            WHEN UAS.Reputation >= 10000 AND UAS.AnswersGiven > 100 AND UAS.TotalPostScore > 5000 THEN 'Elite'
            WHEN UAS.Reputation >= 5000 AND UAS.AnswersGiven > 50 THEN 'Advanced'
            WHEN UAS.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Novice'
        END AS AnswererTier,
        COALESCE(UAS.DisplayName, A.OwnerDisplayName, 'Community User') AS AnswererDisplayName
    FROM
        Posts A
    INNER JOIN
        UserActivitySummary UAS ON A.OwnerUserId = UAS.UserId
    WHERE
        A.PostTypeId = 2
),
TagFrequency AS (
    -- CTE 6: Calculates tag frequencies and associated metrics, linking to expert answerers.
    -- Uses UNNEST to process array of tags, which can result in multiple rows per question.
    SELECT
        UNNEST(QEM.TagArray) AS TagName,
        COUNT(DISTINCT QEM.QuestionId) AS TaggedQuestionsCount,
        AVG(QEM.QuestionScore) AS AvgQuestionScoreForTag,
        AVG(QEM.ViewCount) AS AvgViewCountForTag,
        COUNT(DISTINCT EA.AnswererUserId) AS UniqueAcceptedAnswerersForTag
    FROM
        QuestionEngagementMetrics QEM
    LEFT JOIN
        ExpertAnswerers EA ON QEM.AcceptedAnswerId = EA.AnswerId
    WHERE UNNEST(QEM.TagArray) IS NOT NULL
    GROUP BY
        UNNEST(QEM.TagArray)
)
-- Main Query: Combines all CTEs to provide a comprehensive view of highly engaged questions.
-- Features: intricate joins, multiple correlated subqueries, complex predicates, string manipulations,
-- date arithmetic, and advanced window functions.
SELECT
    QEM.QuestionId,
    QEM.QuestionTitle,
    QEM.QuestionCreationDate,
    QEM.QuestionScore,
    QEM.ViewCount,
    QEM.DeclaredAnswerCount,
    QEM.ActualAnswerCount,
    QEM.CommentCount AS TotalQuestionComments,
    QEM.FavoriteCount,
    QEM.AvgAnswerScore,
    QEM.TotalAnswerScore,
    UAS_Q.DisplayName AS QuestionOwnerName,
    UAS_Q.Reputation AS QuestionOwnerReputation,
    UAS_Q.GoldBadges AS QuestionOwnerGoldBadges,
    QEM.CloseReasonName,
    QEM.WasClosedFlag AS WasClosed,
    QEM.WasReopenedFlag AS WasReopened,
    QEM.EditHistoryCount,
    QEM.ViewCountQuartile,
    QEM.FavoriteRank,
    EA.AnswererDisplayName,
    EA.AnswererReputation,
    EA.AnswererTier,
    EA.AnswerScore AS AcceptedAnswerScore,
    COALESCE(TF.TaggedQuestionsCount, 0) AS TagPopularityScore,
    TF.AvgQuestionScoreForTag,
    TF.AvgViewCountForTag,
    TF.UniqueAcceptedAnswerersForTag,
    -- String manipulations and conditional logic
    SUBSTRING(QEM.QuestionTitle FROM POSITION(' ' IN QEM.QuestionTitle) + 1 FOR LENGTH(QEM.QuestionTitle)) AS TitleSuffix,
    LOWER(LEFT(QEM.QuestionTitle, 10)) AS TitlePrefixLower,
    CASE
        WHEN QEM.ActualAnswerCount = 0 THEN 'Unanswered'
        WHEN QEM.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
        ELSE 'Answered (No Accepted)'
    END AS QuestionStatus,
    EXTRACT(WEEK FROM QEM.QuestionCreationDate) AS CreationWeek, -- Date arithmetic
    (UAS_Q.UpVotes - UAS_Q.DownVotes) AS QuestionOwnerNetVotes, -- Simple calculation
    (
        SELECT
            COUNT(DISTINCT PL.RelatedPostId)
        FROM
            PostLinks PL
        WHERE
            PL.PostId = QEM.QuestionId AND PL.LinkTypeId = 1
    ) AS LinkedPostCount, -- Correlated subquery
    (
        SELECT
            COALESCE(AVG(C.Score), 0)
        FROM
            Comments C
        WHERE
            C.PostId = QEM.QuestionId
            AND C.UserId = QEM.QuestionOwnerId
            AND C.CreationDate >= (QEM.CreationDate - INTERVAL '1 year') -- Correlated subquery with date filter
    ) AS AvgOwnerRecentCommentScore,
    (
        SELECT
            COUNT(DISTINCT A.Id)
        FROM
            Posts A
        WHERE
            A.ParentId = QEM.QuestionId
            AND A.OwnerUserId = QEM.QuestionOwnerId
            AND A.PostTypeId = 2
    ) AS OwnerSelfAnswersCount, -- Another correlated subquery
    AVG(EA_AllAnswers.AnswererReputation) OVER (PARTITION BY UNNEST(QEM.TagArray)) AS AvgAnswererReputationForTag, -- Window function over tags
    SUM(CASE WHEN QEM.QuestionOwnerId = EA.AnswererUserId THEN 1 ELSE 0 END) OVER (PARTITION BY QEM.QuestionId) AS OwnerAcceptedTheirOwnAnswer -- Window function with conditional logic
FROM
    QuestionEngagementMetrics QEM
INNER JOIN
    UserActivitySummary UAS_Q ON QEM.QuestionOwnerId = UAS_Q.UserId
LEFT JOIN
    ExpertAnswerers EA ON QEM.AcceptedAnswerId = EA.AnswerId
LEFT JOIN
    Posts A_All ON QEM.QuestionId = A_All.ParentId AND A_All.PostTypeId = 2 -- Join to get all answers for the question
LEFT JOIN
    ExpertAnswerers EA_AllAnswers ON A_All.Id = EA_AllAnswers.AnswerId -- Join ALL answers with ExpertAnswerers for window function
LEFT JOIN
    TagFrequency TF ON UNNEST(QEM.TagArray) = TF.TagName -- Joins via UNNEST, expanding rows for each tag
WHERE
    QEM.QuestionCreationDate >= '2020-01-01'
    AND QEM.ViewCount >= 500
    AND QEM.QuestionScore > 20
    AND QEM.WasClosedFlag = 0
    AND (QEM.CloseReasonName IS NULL OR QEM.CloseReasonName NOT LIKE '%Duplicate%') -- NULL and string matching logic
    AND (UAS_Q.Reputation > 2000 OR UAS_Q.GoldBadges > 0)
    AND (EA.AnswererTier = 'Elite' OR EA.AnswererTier = 'Advanced' OR QEM.AcceptedAnswerId IS NULL) -- NULL logic for no accepted answer
    AND LENGTH(COALESCE(QEM.QuestionTitle, '')) > 10 -- String length check with NULL handling
ORDER BY
    QEM.FavoriteRank ASC, QEM.ViewCount DESC, QEM.QuestionCreationDate DESC, QEM.QuestionId ASC
LIMIT 1000;
