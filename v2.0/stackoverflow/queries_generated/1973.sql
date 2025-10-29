-- {"query": "1973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4007} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity, reputation, and badge distribution.
    -- Demonstrates LEFT JOINs, COALESCE for NULL handling, and complex arithmetic for scoring.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotesGiven,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(MAX(P.LastActivityDate), U.LastAccessDate) AS LatestActivityDate,
        (U.Reputation * 0.5) + (COUNT(DISTINCT P.Id) * 0.2) + (COUNT(DISTINCT C.Id) * 0.1) + (U.UpVotes - U.DownVotes * 0.5) AS UserActivityScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostQualityAndHistory AS (
    -- CTE 2: Analyzes post quality, edit history, and related metadata for questions and answers.
    -- Utilizes window functions, string manipulation, correlated subqueries, and CASE expressions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.ClosedDate,
        P.Tags,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId) AS AvgOwnerPostScore,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS ScoreRank,
        (SELECT COUNT(DISTINCT PH_sub.UserId)
         FROM PostHistory PH_sub
         WHERE PH_sub.PostId = P.Id
           AND PH_sub.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        ) AS UniqueEditorCount,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsDuplicate,
        -- Extracts the first tag from the Tags string (e.g., "<tag1><tag2>" -> "tag1")
        NULLIF(SUBSTRING(P.Tags FROM (POSITION('<' IN P.Tags) + 1) FOR (POSITION('>' IN P.Tags) - POSITION('<' IN P.Tags) - 1)), '') AS FirstTagRaw,
        EXTRACT(DAY FROM (NOW() - P.CreationDate)) AS PostAgeDays,
        CASE
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN P.OwnerUserId IS NULL THEN 'Community User'
            ELSE 'User Owned'
        END AS OwnershipStatus,
        (P.Score * 0.7) + (COALESCE(P.ViewCount, 0) * 0.1) + (COALESCE(P.CommentCount, 0) * 0.15) + (COALESCE(P.FavoriteCount, 0) * 0.2)
        + CASE WHEN P.LastActivityDate > NOW() - INTERVAL '30 days' THEN 10 ELSE 0 END AS PostActivityScore
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId -- Assumes PostId is the source of the link, e.g., PostId is a duplicate of RelatedPostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
      AND P.CreationDate >= NOW() - INTERVAL '2 years' -- Only relatively recent posts
    GROUP BY
        P.Id, P.PostTypeId, PT.Name, P.Title, P.CreationDate, P.LastEditDate, P.LastActivityDate,
        P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.ClosedDate, P.Tags
),
TagAnalysis AS (
    -- CTE 3: Analyzes tag distribution, average scores, and closure rates for questions.
    SELECT
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(P.Id) AS TotalPostsWithTag,
        AVG(P.Score) AS AvgTagScore,
        MAX(P.ViewCount) AS MaxViewCountForTag,
        SUM(CASE WHEN P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END)::DECIMAL * 100 / NULLIF(COUNT(P.Id), 0) AS TagClosurePercentage
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
      AND P.PostTypeId = 1 -- Only analyze tags from questions
    GROUP BY TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))
),
TopQuestionContributors AS (
    -- CTE 4: Identifies top contributors to high-scoring questions based on accepted answers.
    -- Uses a window function to rank users.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        SUM(CASE WHEN PQ.PostTypeId = 2 AND PQ.PostId = Q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersToHighViewQuestions,
        ROW_NUMBER() OVER (ORDER BY UE.Reputation DESC, COUNT(DISTINCT PQ.PostId) DESC) AS UserOverallRank
    FROM UserEngagement UE
    JOIN PostQualityAndHistory PQ ON UE.UserId = PQ.OwnerUserId
    JOIN Posts Q ON PQ.PostId = Q.AcceptedAnswerId AND Q.PostTypeId = 1 -- Joins answer to its parent question
    WHERE Q.ViewCount > 5000 AND Q.Score > 50
    GROUP BY UE.UserId, UE.DisplayName, UE.Reputation
    HAVING COUNT(DISTINCT PQ.PostId) > 10 -- Users with at least 10 accepted answers on popular questions
),
ComplexQuestionStats AS (
    -- CTE 5: Detailed statistics for questions, including close vote counts and comment analysis.
    -- Features NTILE for distribution, correlated subqueries, and conditional aggregation.
    SELECT
        P.Id AS QuestionId,
        P.Title AS QuestionTitle,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        (SELECT COUNT(*) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS CloseVoteCount,
        NTILE(4) OVER (ORDER BY P.ViewCount DESC) AS ViewCountQuartile,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' THEN 1 ELSE 0 END) AS CommentsMentioningIssues,
        COALESCE(P.ClosedDate IS NOT NULL, FALSE) AS IsClosedQuestion,
        EXTRACT(EPOCH FROM (COALESCE(P.ClosedDate, P.LastActivityDate) - P.CreationDate)) / 3600 AS HoursToCloseOrLastActivity,
        (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScoreForQuestion
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY P.Id, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.ClosedDate, P.LastActivityDate
)
-- Main Query: Combines data from all CTEs.
-- Uses UNION ALL to present two distinct perspectives: high-activity focused vs. noteworthy historical posts.
SELECT
    'ActiveUserAndPost' AS RecordType,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    PQ.PostId,
    PQ.PostTypeName,
    PQ.Title AS PostTitle,
    PQ.Score AS PostScore,
    PQ.ViewCount AS PostViewCount,
    PQ.UniqueEditorCount,
    PQ.IsDuplicate,
    PQ.FirstTagRaw AS MainTag,
    TA.AvgTagScore,
    TQC.AcceptedAnswersToHighViewQuestions,
    CQS.CloseVoteCount,
    CQS.IsClosedQuestion,
    LOWER(REPLACE(REPLACE(REPLACE(COALESCE(PQ.Title, 'No Title Provided'), ' ', '-'), '.', ''), ',', '')) AS PostSlug, -- String expression for URL-like slug
    EXTRACT(YEAR FROM UE.UserCreationDate) AS UserAccountYear,
    UE.UserActivityScore,
    PQ.PostActivityScore,
    -- Complicated predicate/expression using CASE WHEN and NULL logic
    CASE
        WHEN PQ.ClosedDate IS NOT NULL AND PQ.UniqueEditorCount > 2 THEN 'Closed & Heavily Edited'
        WHEN PQ.IsDuplicate = 1 THEN 'Potential Duplicate'
        WHEN PQ.PostAgeDays > 365 AND PQ.Score < 10 THEN 'Old & Low Score'
        ELSE 'Active/Normal'
    END AS PostStatusClassification,
    COALESCE(TA.AvgTagScore, 0.0) AS CoalescedAvgTagScore, -- NULL logic for tag average score
    NTILE(5) OVER (ORDER BY UE.Reputation DESC) AS ReputationQuintile, -- Window function for user reputation distribution
    (SELECT C.Text FROM Comments C WHERE C.PostId = PQ.PostId ORDER BY C.CreationDate DESC LIMIT 1) AS LatestCommentText -- Correlated subquery for latest comment
FROM UserEngagement UE
JOIN PostQualityAndHistory PQ ON UE.UserId = PQ.OwnerUserId
LEFT JOIN TagAnalysis TA ON TA.TagName = PQ.FirstTagRaw
LEFT JOIN TopQuestionContributors TQC ON UE.UserId = TQC.UserId
LEFT JOIN ComplexQuestionStats CQS ON PQ.PostId = CQS.QuestionId
WHERE
    UE.Reputation > 500
    AND PQ.PostScore > 5
    AND PQ.PostTypeId = 1 -- Focusing on Questions
    AND PQ.ViewCount > 1000
    AND (LOWER(PQ.Title) LIKE '%database%' OR LOWER(PQ.Title) LIKE '%sql%' OR LOWER(PQ.Tags) LIKE '%<javascript>%' OR LOWER(PQ.Tags) LIKE '%<python>%') -- Complicated predicate using string expressions
    AND PQ.PostActivityScore > 50
    AND CQS.ViewCountQuartile = 1
    AND COALESCE(TA.TagClosurePercentage, 0) < 50
UNION ALL
-- Secondary query branch: focuses on "noteworthy" posts (duplicates, heavily edited, old with high engagement)
-- Uses OUTER JOINs to include posts or users that might not meet strict activity criteria.
SELECT
    'NoteworthyPost' AS RecordType,
    COALESCE(UE.UserId, -1) AS UserId,
    COALESCE(UE.DisplayName, 'Unknown User') AS DisplayName,
    COALESCE(UE.Reputation, 0) AS Reputation,
    COALESCE(UE.TotalPosts, 0) AS TotalPosts,
    COALESCE(UE.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(UE.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(UE.GoldBadges, 0) AS GoldBadges,
    COALESCE(UE.SilverBadges, 0) AS SilverBadges,
    COALESCE(UE.BronzeBadges, 0) AS BronzeBadges,
    PQ.PostId,
    PQ.PostTypeName,
    PQ.Title AS PostTitle,
    PQ.Score AS PostScore,
    PQ.ViewCount AS PostViewCount,
    PQ.UniqueEditorCount,
    PQ.IsDuplicate,
    PQ.FirstTagRaw AS MainTag,
    TA.AvgTagScore,
    COALESCE(TQC.AcceptedAnswersToHighViewQuestions, 0) AS AcceptedAnswersToHighViewQuestions,
    CQS.CloseVoteCount,
    CQS.IsClosedQuestion,
    LOWER(REPLACE(REPLACE(REPLACE(COALESCE(PQ.Title, 'No Title Provided'), ' ', '-'), '.', ''), ',', '')) AS PostSlug,
    EXTRACT(YEAR FROM COALESCE(UE.UserCreationDate, '1970-01-01')) AS UserAccountYear,
    COALESCE(UE.UserActivityScore, 0.0) AS UserActivityScore,
    PQ.PostActivityScore,
    CASE
        WHEN PQ.IsDuplicate = 1 THEN 'Potential Duplicate (Noteworthy)'
        WHEN PQ.UniqueEditorCount > 5 AND PQ.LastEditDate > NOW() - INTERVAL '90 days' THEN 'Heavily Edited Recently (Noteworthy)'
        WHEN PQ.PostAgeDays > 730 AND PQ.CommentCount > 20 THEN 'Old with High Comment Engagement (Noteworthy)'
        WHEN CQS.CommentsMentioningIssues > 0 THEN 'Question with Reported Issues (Noteworthy)'
        ELSE 'Other Noteworthy'
    END AS PostStatusClassification,
    COALESCE(TA.AvgTagScore, 0.0) AS CoalescedAvgTagScore,
    NULL AS ReputationQuintile, -- NTILE not applied to this branch as focus is not on user rank
    (SELECT C.Text FROM Comments C WHERE C.PostId = PQ.PostId ORDER BY C.CreationDate DESC LIMIT 1) AS LatestCommentText
FROM PostQualityAndHistory PQ
LEFT JOIN UserEngagement UE ON PQ.OwnerUserId = UE.UserId
LEFT JOIN TagAnalysis TA ON TA.TagName = PQ.FirstTagRaw
LEFT JOIN TopQuestionContributors TQC ON UE.UserId = TQC.UserId
LEFT JOIN ComplexQuestionStats CQS ON PQ.PostId = CQS.QuestionId
WHERE
    (PQ.IsDuplicate = 1
    OR (PQ.UniqueEditorCount > 5 AND PQ.LastEditDate > NOW() - INTERVAL '90 days')
    OR (PQ.PostAgeDays > 730 AND PQ.CommentCount > 20)
    OR CQS.CommentsMentioningIssues > 0
    )
    AND PQ.PostTypeId = 1
    -- Exclude posts already covered by the first UNION ALL branch to ensure distinctness
    AND PQ.PostId NOT IN (SELECT FirstBranchQ.PostId FROM (
        SELECT PQC.PostId FROM UserEngagement UEC
        JOIN PostQualityAndHistory PQC ON UEC.UserId = PQC.OwnerUserId
        LEFT JOIN TagAnalysis TAC ON TAC.TagName = PQC.FirstTagRaw
        LEFT JOIN ComplexQuestionStats CQSC ON PQC.PostId = CQSC.QuestionId
        WHERE
            UEC.Reputation > 500 AND PQC.PostScore > 5 AND PQC.PostTypeId = 1 AND PQC.ViewCount > 1000
            AND (LOWER(PQC.Title) LIKE '%database%' OR LOWER(PQC.Title) LIKE '%sql%' OR LOWER(PQC.Tags) LIKE '%<javascript>%' OR LOWER(PQC.Tags) LIKE '%<python>%')
            AND PQC.PostActivityScore > 50 AND CQSC.ViewCountQuartile = 1 AND COALESCE(TAC.TagClosurePercentage, 0) < 50
    ) AS FirstBranchQ)
ORDER BY
    RecordType DESC, -- Noteworthy posts first, then Active. (Adjust DESC/ASC based on desired output)
    UserActivityScore DESC,
    PostActivityScore DESC
LIMIT 500;
