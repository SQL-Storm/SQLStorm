-- {"query": "1316.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3191} 

WITH UserPostEngagement AS (
    -- Summarize user activity: posts, comments, votes, applying conditional aggregates and date math
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P_Q.Id) AS TotalQuestionsAsked,
        SUM(CASE WHEN P_Q.CreationDate >= (U.CreationDate + INTERVAL '1 year') THEN 1 ELSE 0 END) AS QuestionsAfterFirstYear, -- Complicated predicate/date arithmetic
        SUM(P_Q.ViewCount) AS TotalQuestionViews,
        AVG(COALESCE(P_Q.Score, 0)) AS AvgQuestionScore, -- NULL logic, COALESCE
        COUNT(DISTINCT P_A.Id) AS TotalAnswersGiven,
        AVG(COALESCE(P_A.Score, 0)) AS AvgAnswerScore,
        SUM(CASE WHEN P_Q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        MAX(P_Q.CreationDate) AS LatestQuestionDate,
        MAX(P_A.CreationDate) AS LatestAnswerDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Users U
    LEFT JOIN Posts P_Q ON U.Id = P_Q.OwnerUserId AND P_Q.PostTypeId = 1 -- Questions
    LEFT JOIN Posts P_A ON U.Id = P_A.OwnerUserId AND P_A.PostTypeId = 2 -- Answers
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.CreationDate, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
UserBadgeSummary AS (
    -- Determine highest badge class and total badges for each user
    SELECT
        U.Id AS UserId,
        MIN(B.Class) AS HighestBadgeClass, -- 1 (Gold), 2 (Silver), 3 (Bronze) - MIN() for highest prestige
        COUNT(B.Id) AS TotalBadges
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
PostTagAnalysis AS (
    -- Analyze tags for questions, including string operations and correlated subquery for known tags
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.Title,
        P.Tags,
        P.LastActivityDate,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS NumberOfTags, -- String expression/array manipulation
        (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%') AS HasRelevantTags, -- String expression/complicated predicate
        (SELECT COUNT(T.Id) FROM Tags T WHERE T.TagName IN (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))) AS DistinctKnownTags -- Correlated subquery, array unnest
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Filter for valid tags
),
QuestionAnswerScores AS (
    -- Calculate scores for answers related to questions, with window functions for ranking
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        A.Id AS AnswerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY Q.Id ORDER BY A.Score DESC, A.CreationDate DESC) AS AnswerScoreRankDesc, -- Window function
        LAG(A.Score, 1, 0) OVER (PARTITION BY Q.Id ORDER BY A.CreationDate ASC) AS PreviousAnswerScore -- Window function
    FROM Posts Q
    JOIN Posts A ON Q.Id = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
),
UserTopComments AS (
    -- Identify the top 3 most recent comments made by each user using a window function
    SELECT
        C.UserId,
        C.Id AS CommentId,
        C.Text,
        C.CreationDate AS CommentCreationDate,
        ROW_NUMBER() OVER (PARTITION BY C.UserId ORDER BY C.CreationDate DESC) AS rn
    FROM Comments C
),
PostEditActivity AS (
    -- Track post edit history with a window function for edit ranking
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS EditRank
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
)
-- Main query: Combines user data, post metrics, badge info, and more complex analytics
SELECT
    UPE.UserId,
    UPE.DisplayName,
    UPE.Reputation,
    UPE.UserCreationDate,
    COALESCE(UBS.HighestBadgeClass, 99) AS UserHighestBadgeClass, -- NULL logic (99 for no badges)
    UBS.TotalBadges,
    UPE.TotalQuestionsAsked,
    UPE.TotalAnswersGiven,
    UPE.TotalCommentsMade,
    NULLIF(UPE.AvgQuestionScore, 0.0) AS AvgQuestionScoreAdjusted, -- NULLIF example (avoiding 0 when no questions)
    UPE.AvgAnswerScore,
    QA.PostId AS TopQuestionWithRelevantTag,
    QA.Title AS TopQuestionTitle,
    QA.Score AS TopQuestionScore,
    QA.NumberOfTags AS TopQuestionTagCount,
    QA.DistinctKnownTags AS TopQuestionDistinctKnownTags,
    (SELECT AVG(QAS.AnswerScore) FROM QuestionAnswerScores QAS WHERE QAS.QuestionOwnerId = UPE.UserId) AS OverallAvgAnswerScoreToUserQuestions, -- Correlated subquery
    (SELECT MAX(QAS.AnswerScore) FROM QuestionAnswerScores QAS WHERE QAS.QuestionOwnerId = UPE.UserId AND QAS.AnswerScoreRankDesc = 1) AS HighestAnswerScoreToUserQuestions, -- Correlated subquery
    DATE_PART('day', NOW() - UPE.UserCreationDate) AS DaysSinceRegistration, -- Date calculation
    CASE -- Complicated expression with CASE
        WHEN UPE.TotalQuestionsAsked > 0 AND UPE.TotalAnswersGiven = 0 THEN 'Questioner Only'
        WHEN UPE.TotalQuestionsAsked = 0 AND UPE.TotalAnswersGiven > 0 THEN 'Answerer Only'
        WHEN UPE.TotalQuestionsAsked > 0 AND UPE.TotalAnswersGiven > 0 THEN 'Contributor'
        ELSE 'Lurker/Commenter'
    END AS UserRoleCategory,
    SUM(CASE WHEN PLA.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount, -- Conditional aggregate
    SUM(CASE WHEN PLA.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount, -- Conditional aggregate
    NTILE(5) OVER (ORDER BY UPE.Reputation DESC) AS ReputationQuintile, -- Window function
    RANK() OVER (PARTITION BY COALESCE(UBS.HighestBadgeClass, 99) ORDER BY UPE.TotalQuestionsAsked DESC, UPE.TotalAnswersGiven DESC) AS RankInBadgeClass, -- Window function with NULL logic in partition
    STRING_AGG(UTC.Text, ' ||| ') FILTER (WHERE UTC.rn <= 3) AS Top3CommentTexts, -- String aggregation with FILTER for top N
    PEA_Q.EditorUserId AS LastQuestionEditor,
    PEA_Q.EditDate AS LastQuestionEditDate,
    (SELECT AVG(PEA_Inner.EditRank) FROM PostEditActivity PEA_Inner JOIN Posts P_Inner ON PEA_Inner.PostId = P_Inner.Id WHERE P_Inner.OwnerUserId = UPE.UserId AND PEA_Inner.EditorUserId = UPE.UserId) AS AvgEditRankBySelfForOwnPosts -- Correlated aggregate subquery
FROM UserPostEngagement UPE
LEFT JOIN UserBadgeSummary UBS ON UPE.UserId = UBS.UserId
LEFT JOIN LATERAL ( -- LATERAL join to get top question with relevant tags for the current user
    SELECT PTA.PostId, PTA.Title, PTA.Score, PTA.NumberOfTags, PTA.DistinctKnownTags
    FROM PostTagAnalysis PTA
    WHERE PTA.OwnerUserId = UPE.UserId
      AND PTA.HasRelevantTags
    ORDER BY PTA.Score DESC, PTA.CreationDate DESC
    LIMIT 1
) AS QA ON TRUE
LEFT JOIN PostLinks PLA ON UPE.UserId = (SELECT P.OwnerUserId FROM Posts P WHERE P.Id = PLA.PostId LIMIT 1) -- Outer join to PostLinks, requiring a subquery for OwnerUserId
LEFT JOIN UserTopComments UTC ON UPE.UserId = UTC.UserId AND UTC.rn <= 3 -- Join to get top 3 comments
LEFT JOIN LATERAL ( -- LATERAL join to find the last editor for any of the user's questions
    SELECT PEA.EditorUserId, PEA.EditDate
    FROM PostEditActivity PEA
    JOIN Posts P ON PEA.PostId = P.Id
    WHERE P.OwnerUserId = UPE.UserId AND PEA.EditRank = 1
    ORDER BY PEA.EditDate DESC
    LIMIT 1
) AS PEA_Q ON TRUE
WHERE UPE.TotalQuestionsAsked > 0
  AND COALESCE(UBS.HighestBadgeClass, 99) = 1 -- Only Gold badge users (or users without badges if 99 is desired for "no badge")
  AND (SELECT MAX(QAS.AnswerScore) FROM QuestionAnswerScores QAS WHERE QAS.QuestionOwnerId = UPE.UserId AND QAS.AnswerScoreRankDesc = 1) > 10 -- Correlated subquery in WHERE
  AND UPE.DisplayName IS NOT NULL AND TRIM(UPE.DisplayName) <> '' -- NULL logic and string checks
GROUP BY
    UPE.UserId, UPE.DisplayName, UPE.Reputation, UPE.UserCreationDate,
    UBS.HighestBadgeClass, UBS.TotalBadges,
    UPE.TotalQuestionsAsked, UPE.TotalAnswersGiven, UPE.TotalCommentsMade,
    UPE.AvgQuestionScore, UPE.AvgAnswerScore,
    QA.PostId, QA.Title, QA.Score, QA.NumberOfTags, QA.DistinctKnownTags,
    PEA_Q.EditorUserId, PEA_Q.EditDate
HAVING
    COUNT(DISTINCT PLA.PostId) > 0 OR SUM(CASE WHEN UPE.QuestionsWithAcceptedAnswer > 0 THEN 1 ELSE 0 END) > 0 -- Complicated HAVING clause with OR logic
UNION ALL -- Set operator: UNION ALL to combine with a different group of users (commenters only)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    COALESCE(UBS.HighestBadgeClass, 99) AS UserHighestBadgeClass,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    0 AS TotalQuestionsAsked,
    0 AS TotalAnswersGiven,
    COUNT(DISTINCT C.Id) AS TotalCommentsMade,
    0.0 AS AvgQuestionScoreAdjusted,
    0.0 AS AvgAnswerScore,
    NULL AS TopQuestionWithRelevantTag,
    NULL AS TopQuestionTitle,
    NULL AS TopQuestionScore,
    NULL AS TopQuestionTagCount,
    NULL AS TopQuestionDistinctKnownTags,
    0.0 AS OverallAvgAnswerScoreToUserQuestions,
    0 AS HighestAnswerScoreToUserQuestions,
    DATE_PART('day', NOW() - U.CreationDate) AS DaysSinceRegistration,
    'Commenter Only (No Posts/Gold Badge)' AS UserRoleCategory,
    0 AS LinkedPostsCount,
    0 AS DuplicatePostsCount,
    NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile, -- Window function
    RANK() OVER (ORDER BY COUNT(DISTINCT C.Id) DESC) AS RankInBadgeClass, -- Window function
    STRING_AGG(UTC.Text, ' ||| ') FILTER (WHERE UTC.rn <= 3) AS Top3CommentTexts, -- String aggregation
    NULL AS LastQuestionEditor,
    NULL AS LastQuestionEditDate,
    NULL AS AvgEditRankBySelfForOwnPosts
FROM Users U
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN Comments C ON U.Id = C.UserId
LEFT JOIN UserTopComments UTC ON U.Id = UTC.UserId AND UTC.rn <= 3
WHERE U.Id NOT IN (SELECT UserId FROM UserBadgeSummary WHERE HighestBadgeClass = 1) -- Users without Gold badges (NOT IN, effectively EXCEPT)
  AND NOT EXISTS (SELECT 1 FROM Posts P WHERE P.OwnerUserId = U.Id) -- Users who haven't owned any posts (NOT EXISTS)
  AND COUNT(DISTINCT C.Id) > 5 -- Users who made at least 5 comments
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate,
    UBS.HighestBadgeClass, UBS.TotalBadges
ORDER BY
    Reputation DESC, DaysSinceRegistration ASC;
