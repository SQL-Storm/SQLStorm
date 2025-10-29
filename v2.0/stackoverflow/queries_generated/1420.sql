-- {"query": "1420.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3018} 

WITH UserEngagementSummary AS (
    -- Calculates various engagement metrics for users, including question/answer counts, total views, and comment scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersPosted,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(P.Score) AS TotalPostsScore,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Calculate the median score of the user's answers for performance insights
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Ans.Score) FILTER (WHERE Ans.Id IS NOT NULL) AS MedianAnswerScore
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Posts AS Ans ON U.Id = Ans.OwnerUserId AND Ans.PostTypeId = 2
    GROUP BY U.Id, U.DisplayName
),
PostHistoryAggregated AS (
    -- Aggregates post history details, focusing on edits, close reasons, and unique editors.
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS TotalEditRollbackCount, -- Edit and Rollback events
        MAX(PH.CreationDate) AS LastHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '10%' THEN 1 ELSE 0 END) AS WasClosedRecently, -- Current close reasons
        COUNT(DISTINCT PH.UserId) AS UniqueEditorsPerPost,
        -- Detect specific text patterns in post history comments
        MAX(CASE WHEN PH.Comment ILIKE '%duplicate%' OR PH.Text ILIKE '%originalquestionids%' THEN 1 ELSE 0 END) AS HasDuplicateReference
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId BETWEEN 1 AND 38 -- Focus on core history types
    GROUP BY PH.PostId
),
TagComplexityAnalysis AS (
    -- Analyzes tag count and average tag length for questions, handling NULLs and parsing.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS TagCount,
        -- Calculate average tag length using UNNEST for array expansion (PostgreSQL specific)
        (
            SELECT AVG(LENGTH(t.tag_name))
            FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS t(tag_name)
        ) AS AvgTagLength,
        P.Tags AS RawTagsString,
        -- Check if specific "difficult" tags are present
        CASE
            WHEN P.Tags LIKE '%<c++>%' OR P.Tags LIKE '%<java>%' OR P.Tags LIKE '%<python>%' THEN TRUE
            ELSE FALSE
        END AS HasComplexTags
    FROM Posts AS P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
RelatedPostsMetrics AS (
    -- Quantifies linked and duplicated posts for each question.
    SELECT
        PL.PostId,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId END) AS LinkedPostCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateOfCount, -- How many times this post is a duplicate of another
        COUNT(DISTINCT P_Link.Id) AS TotalPostsRelatedToThisQuestion,
        SUM(CASE WHEN PL.LinkTypeId = 1 AND P_Link.Score > 0 THEN P_Link.Score ELSE 0 END) AS LinkedPostAggregateScore,
        MAX(PL.CreationDate) AS LatestLinkActivityDate
    FROM PostLinks AS PL
    LEFT JOIN Posts AS P_Link ON PL.RelatedPostId = P_Link.Id
    INNER JOIN Posts AS P_Question ON PL.PostId = P_Question.Id WHERE P_Question.PostTypeId = 1
    GROUP BY PL.PostId
),
UserBadgesRanking AS (
    -- Ranks users based on their badge achievements and counts.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE B.Class WHEN 1 THEN 300 WHEN 2 THEN 100 WHEN 3 THEN 10 ELSE 0 END) AS WeightedBadgeScore,
        MAX(B.Date) AS LatestBadgeAwardDate,
        -- Rank users by weighted badge score, then by total badges
        DENSE_RANK() OVER (ORDER BY SUM(CASE B.Class WHEN 1 THEN 300 WHEN 2 THEN 100 WHEN 3 THEN 10 ELSE 0 END) DESC, COUNT(B.Id) DESC) AS UserBadgeRank
    FROM Badges AS B
    GROUP BY B.UserId
),
UserQuestionPerformance AS (
    -- Evaluates individual question performance for each user using window functions.
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AcceptedAnswerId,
        -- Rank questions by score within each user's history
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS UserQuestionScoreRank,
        -- Calculate the difference in view count from the user's previous question
        P.ViewCount - LAG(P.ViewCount, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS ViewCountDeltaFromPrevious,
        -- Cumulative sum of views for the user's questions up to the current one
        SUM(P.ViewCount) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS CumulativeQuestionViews,
        -- Average score of the user's questions in the past 5 posts
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingAvgScoreLast5Questions,
        -- Correlated subquery: check if any comment on this question received a high score
        (
            SELECT MAX(CASE WHEN C.Score > 5 THEN 1 ELSE 0 END)
            FROM Comments C
            WHERE C.PostId = P.Id
        ) AS HasHighlyScoredComment
    FROM Posts AS P
    WHERE P.PostTypeId = 1
)
-- Main query: Combines and refines data from all CTEs to generate a comprehensive user performance benchmark.
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserAccountCreationDate,
    U.LastAccessDate,
    UES.TotalQuestionsPosted,
    UES.TotalAnswersPosted,
    UES.TotalQuestionViews,
    UES.TotalPostsScore,
    UES.QuestionsWithAcceptedAnswers,
    UES.TotalCommentsMade,
    UES.MedianAnswerScore,
    UBR.TotalBadges,
    UBR.WeightedBadgeScore,
    UBR.UserBadgeRank,
    MAX(UQP.RollingAvgScoreLast5Questions) AS MaxRollingAvgScore,
    MIN(UQP.UserQuestionScoreRank) AS BestQuestionRankByUser,
    SUM(COALESCE(PHA.TotalEditRollbackCount, 0)) AS TotalHistoryModifications,
    SUM(CASE WHEN PHA.WasClosedRecently = 1 THEN 1 ELSE 0 END) AS QuestionsClosedRecentlyCount,
    SUM(CASE WHEN PHA.UniqueEditorsPerPost > 1 THEN 1 ELSE 0 END) AS PostsWithMultipleEditors,
    SUM(COALESCE(RPM.LinkedPostCount, 0)) AS TotalLinkedQuestions,
    SUM(COALESCE(RPM.DuplicateOfCount, 0)) AS TotalDuplicateReferences,
    AVG(TCA.AvgTagLength) FILTER (WHERE TCA.AvgTagLength IS NOT NULL) AS AverageQuestionTagLength,
    MAX(TCA.HasComplexTags) AS HasPostedComplexTagQuestion,
    -- Complex NULL handling and string manipulation for Location and WebsiteUrl
    COALESCE(
        NULLIF(TRIM(SUBSTRING(U.Location, 1, POSITION(',' IN U.Location) - 1)), ''),
        NULLIF(TRIM(U.Location), '')) AS PrimaryLocationSegment,
    CASE
        WHEN U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl LIKE 'http://%' THEN 'HTTP'
        WHEN U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl LIKE 'https://%' THEN 'HTTPS'
        WHEN U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl LIKE '%stackexchange.com%' THEN 'SE_Link'
        ELSE 'Other/None'
    END AS WebsiteProtocolType,
    -- Correlated subquery to find if the user has a post with high score and many comments
    (
        SELECT
            CASE
                WHEN COUNT(DISTINCT P_HighPerf.Id) > 0 THEN TRUE
                ELSE FALSE
            END
        FROM Posts P_HighPerf
        WHERE P_HighPerf.OwnerUserId = U.Id
          AND P_HighPerf.PostTypeId = 1
          AND P_HighPerf.Score >= 100
          AND P_HighPerf.CommentCount >= 10
    ) AS HasHighPerformanceQuestion,
    -- Correlated subquery using a set operator concept (EXCEPT equivalent)
    (
        SELECT COUNT(DISTINCT P_Q.Id)
        FROM Posts P_Q
        WHERE P_Q.OwnerUserId = U.Id AND P_Q.PostTypeId = 1
        EXCEPT
        SELECT DISTINCT P_A.ParentId
        FROM Posts P_A
        WHERE P_A.OwnerUserId = U.Id AND P_A.PostTypeId = 2
    ) AS UnansweredQuestionsCountByThisUser,
    -- Lag/Lead for user's last access date relative to creation date
    EXTRACT(DAY FROM (U.LastAccessDate - U.CreationDate)) AS DaysSinceCreationToLastAccess
FROM Users AS U
INNER JOIN UserEngagementSummary AS UES ON U.Id = UES.UserId
LEFT JOIN UserBadgesRanking AS UBR ON U.Id = UBR.UserId
LEFT JOIN UserQuestionPerformance AS UQP ON U.Id = UQP.OwnerUserId
LEFT JOIN Posts AS P_UserOwned ON U.Id = P_UserOwned.OwnerUserId -- Join for post-level details that are not aggregated in UES
LEFT JOIN PostHistoryAggregated AS PHA ON P_UserOwned.Id = PHA.PostId
LEFT JOIN TagComplexityAnalysis AS TCA ON P_UserOwned.Id = TCA.PostId AND P_UserOwned.PostTypeId = 1
LEFT JOIN RelatedPostsMetrics AS RPM ON P_UserOwned.Id = RPM.PostId
WHERE
    U.Reputation >= 5000 -- Filter for users with significant reputation
    AND UES.TotalQuestionsPosted >= 10
    AND UES.TotalAnswersPosted >= 5
    AND UBR.WeightedBadgeScore IS NOT NULL -- Users must have at least one badge
    AND UQP.QuestionId IS NOT NULL -- Ensure user has at least one question in UQP
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
    UES.TotalQuestionsPosted, UES.TotalAnswersPosted, UES.TotalQuestionViews, UES.TotalPostsScore,
    UES.QuestionsWithAcceptedAnswers, UES.TotalCommentsMade, UES.MedianAnswerScore,
    UBR.TotalBadges, UBR.WeightedBadgeScore, UBR.UserBadgeRank,
    U.Location, U.WebsiteUrl
HAVING
    COUNT(DISTINCT CASE WHEN UQP.QuestionId IS NOT NULL AND UQP.UserQuestionScoreRank = 1 AND UQP.Score >= 200 THEN UQP.QuestionId END) >= 1
    AND SUM(COALESCE(PHA.TotalEditRollbackCount, 0)) >= 20
    AND AVG(TCA.AvgTagLength) FILTER (WHERE TCA.AvgTagLength IS NOT NULL) > 4.5 -- Average tag length must be substantial
ORDER BY
    UBR.WeightedBadgeScore DESC,
    UES.TotalPostsScore DESC,
    TotalHistoryModifications DESC,
    UserAccountCreationDate ASC
LIMIT 100 OFFSET 10;
