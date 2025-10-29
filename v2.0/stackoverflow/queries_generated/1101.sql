-- {"query": "1101.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3894} 

WITH UserEngagementSummary AS (
    -- Aggregates user activities, including posts, comments, votes, and badges
    -- Calculates various sums and averages for user-level metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, V.CreationDate, U.LastAccessDate)) AS LastKnownActivity,
        AVG(P.Score) FILTER (WHERE P.Score IS NOT NULL) AS AvgPostScore,
        AVG(C.Score) FILTER (WHERE C.Score IS NOT NULL) AS AvgCommentScore,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS TotalPostEditsByOwner
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId AND P.Id = PH.PostId -- Joining PostHistory for edits specifically by the owner
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0 -- Focus on users with at least some activity
),
PostContentDetailedAnalysis AS (
    -- Analyzes individual post characteristics, including length, edit history, and content keywords
    -- Uses correlated subqueries and window functions for detailed post metrics
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        P.ClosedDate,
        P.CommunityOwnedDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(COALESCE(P.Title, '')) AS TitleLength, -- COALESCE for robust length calculation
        -- Correlated subquery to count unique editors excluding the original owner
        (SELECT COUNT(DISTINCT PH_Edit.UserId) FROM PostHistory PH_Edit WHERE PH_Edit.PostId = P.Id AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) AND PH_Edit.UserId != P.OwnerUserId) AS UniqueExternalEditors,
        -- Correlated subquery to calculate average score of answers for a question
        CASE WHEN P.PostTypeId = 1 THEN
            (SELECT AVG(A.Score)
             FROM Posts A
             WHERE A.ParentId = P.Id
               AND A.PostTypeId = 2
               AND A.Score IS NOT NULL)
        ELSE NULL END AS AvgAnswerScoreForQuestion,
        -- Uses ILIKE for case-insensitive keyword search for "performance benchmarking" topics
        (CASE WHEN P.Body ILIKE '%performance%' OR P.Body ILIKE '%optimization%' OR P.Title ILIKE '%benchmark%' THEN 1 ELSE 0 END) AS ContainsPerfKeywords,
        -- Calculate days since the post was last edited, using epoch difference for timestamp calculation
        EXTRACT(EPOCH FROM (NOW() - P.LastEditDate)) / (60*60*24) AS DaysSinceLastEdit,
        -- Window function to rank posts by score within each post type
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreInType
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community-owned posts or deleted user posts for this analysis
),
UserPostTagPreference AS (
    -- Determines the primary tag a user posts about based on their question activity
    SELECT
        PCA.OwnerUserId AS UserId,
        T.TagName,
        COUNT(PCA.PostId) AS TaggedPostCount,
        ROW_NUMBER() OVER (PARTITION BY PCA.OwnerUserId ORDER BY COUNT(PCA.PostId) DESC, T.TagName) AS TagRank
    FROM PostContentDetailedAnalysis PCA
    -- `string_to_array` and `UNNEST` are PostgreSQL specific for splitting tags
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(PCA.Tags, 2, LENGTH(PCA.Tags) - 2), '><')) AS PostTag ON TRUE
    JOIN Tags T ON T.TagName = PostTag
    WHERE PCA.PostTypeId = 1 -- Only consider question tags for user preference
      AND PCA.Tags IS NOT NULL
      AND PCA.OwnerUserId IS NOT NULL
    GROUP BY PCA.OwnerUserId, T.TagName
),
UserTopPostsRanked AS (
    -- Identifies a user's highest scored post of any type
    SELECT
        PostId,
        OwnerUserId,
        Title,
        PostScore,
        ViewCount,
        PostCreationDate,
        RankByScoreInType,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY PostScore DESC, PostCreationDate DESC) AS UserSpecificPostRank
    FROM PostContentDetailedAnalysis
    WHERE OwnerUserId IS NOT NULL
      AND PostTypeId IN (1, 2) -- Consider questions and answers
),
TagUsageMetrics AS (
    -- Aggregates performance metrics for each tag
    SELECT
        T.TagName,
        COUNT(DISTINCT PCA.PostId) AS TotalPostsWithTag,
        AVG(PCA.PostScore) FILTER (WHERE PCA.PostScore IS NOT NULL) AS AvgPostScoreForTag,
        AVG(PCA.ViewCount) FILTER (WHERE PCA.ViewCount IS NOT NULL) AS AvgViewCountForTag,
        SUM(CASE WHEN PCA.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsWithTag,
        SUM(CASE WHEN PCA.PostTypeId = 1 AND PCA.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswerForTag,
        -- Calculates accepted answer rate, handling division by zero with NULLIF
        CAST(SUM(CASE WHEN PCA.PostTypeId = 1 AND PCA.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS DECIMAL) * 100.0 / NULLIF(SUM(CASE WHEN PCA.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS AcceptedAnswerRate
    FROM PostContentDetailedAnalysis PCA
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(PCA.Tags, 2, LENGTH(PCA.Tags) - 2), '><')) AS PostTag ON TRUE
    JOIN Tags T ON T.TagName = PostTag
    WHERE PCA.PostTypeId IN (1, 2)
    GROUP BY T.TagName
),
UserOverallPostStats AS (
    -- Provides aggregated post statistics per user, not available in UserEngagementSummary
    SELECT
        OwnerUserId AS UserId,
        AVG(CASE WHEN PostTypeId = 1 THEN BodyLength ELSE NULL END) FILTER (WHERE BodyLength IS NOT NULL) AS AvgQuestionBodyLength,
        AVG(CASE WHEN PostTypeId = 2 THEN BodyLength ELSE NULL END) FILTER (WHERE BodyLength IS NOT NULL) AS AvgAnswerBodyLength,
        COUNT(CASE WHEN PostTypeId = 1 AND PostScore > 100 AND ContainsPerfKeywords = 1 THEN 1 ELSE NULL END) AS HighScoringPerfQuestions,
        COUNT(CASE WHEN PostTypeId = 2 AND AcceptedAnswerId IS NOT NULL AND PostScore > 50 THEN 1 ELSE NULL END) AS HighScoringAcceptedAnswers
    FROM PostContentDetailedAnalysis
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
-- Main analysis query combining all CTEs to generate a comprehensive user performance report
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.LastKnownActivity,
    UAS.AvgPostScore AS UserOverallAvgPostScore,
    UAS.TotalPostEditsByOwner,
    -- Uses COALESCE for NULL safety if a user has no top post
    COALESCE(UTPR.Title, 'No recent top post') AS TopPostTitle,
    COALESCE(UTPR.PostScore, 0) AS TopPostScore,
    COALESCE(UTPR.ViewCount, 0) AS TopPostViews,
    UPTP.TagName AS PrimaryTagForQuestions,
    TUM.AvgPostScoreForTag AS PrimaryTagAvgPostScore,
    TUM.AcceptedAnswerRate AS PrimaryTagAcceptedAnswerRate,
    UPS.AvgQuestionBodyLength,
    UPS.AvgAnswerBodyLength,
    -- Correlated subquery to find the highest score for an answer by this user to a very popular question
    (SELECT COALESCE(MAX(A.Score), 0)
     FROM Posts Q
     JOIN Posts A ON Q.Id = A.ParentId
     WHERE Q.PostTypeId = 1
       AND A.PostTypeId = 2
       AND A.OwnerUserId = UAS.UserId
       AND Q.ViewCount > 7500 -- Highly viewed questions
       AND A.Score > 0
       AND Q.CreationDate >= NOW() - INTERVAL '3 years'
     ) AS BestAnswerScoreToPopularQuestion,
    -- Correlated subquery: When did the user achieve their first Gold badge?
    (SELECT MIN(B.Date)
     FROM Badges B
     WHERE B.UserId = UAS.UserId AND B.Class = 1
    ) AS FirstGoldBadgeDate,
    -- Calculates a composite user engagement score based on various activity metrics
    (UAS.Reputation * 0.1
     + UAS.TotalQuestions * 0.5
     + UAS.TotalAnswers * 0.7
     + UAS.TotalComments * 0.2
     + UAS.GoldBadges * 10
     + UAS.SilverBadges * 5
     + UAS.BronzeBadges * 1
     + UPS.HighScoringPerfQuestions * 2) AS UserEngagementScore,
    -- Ranks users by a combined metric of reputation, total posts/answers, and recent activity using a DENSE_RANK window function
    DENSE_RANK() OVER (ORDER BY UAS.Reputation DESC, (UAS.TotalQuestions + UAS.TotalAnswers) DESC, UAS.LastKnownActivity DESC) AS OverallUserActivityRank,
    -- Checks if the user has asked high-quality performance-related questions with accepted answers
    (SELECT COUNT(DISTINCT PCDA_Inner.PostId)
     FROM PostContentDetailedAnalysis PCDA_Inner
     WHERE PCDA_Inner.OwnerUserId = UAS.UserId
       AND PCDA_Inner.PostTypeId = 1
       AND PCDA_Inner.ContainsPerfKeywords = 1
       AND PCDA_Inner.PostScore >= 20
       AND PCDA_Inner.AcceptedAnswerId IS NOT NULL) AS HighQualityPerfQuestionsCount,
    -- An elaborate calculation: Average score per year of activity, handling potential division by zero
    COALESCE(
        (UAS.AvgPostScore * 0.8 + UAS.AvgCommentScore * 0.2)
        / NULLIF(
            EXTRACT(EPOCH FROM (NOW() - UAS.UserCreationDate)) / (60*60*24*365.25), -- Years since creation
            0
        ),
        0
    ) AS AvgScorePerYear,
    -- Classifies the user into expertise levels based on badges, reputation, and activity, using a complex CASE statement
    CASE
        WHEN UAS.GoldBadges > 3 AND UAS.Reputation > 100000 AND UAS.LastAccessDate >= NOW() - INTERVAL '3 months' THEN 'Legendary Contributor (Active)'
        WHEN UAS.GoldBadges > 0 AND UAS.Reputation > 25000 AND UAS.TotalAnswers > 50 THEN 'Specialist Expert'
        WHEN UAS.TotalQuestions > 100 AND UAS.TotalAnswers > 100 AND UAS.LastAccessDate >= NOW() - INTERVAL '6 months' THEN 'Highly Active Generalist'
        WHEN UAS.TotalBadges > 20 AND UAS.LastKnownActivity >= NOW() - INTERVAL '1 year' THEN 'Engaged Member'
        WHEN UAS.TotalPosts > 5 AND UAS.Reputation > 500 AND UAS.UserCreationDate >= NOW() - INTERVAL '1 year' THEN 'Promising Newcomer'
        ELSE 'Casual User'
    END AS UserCategory
FROM UserEngagementSummary UAS
LEFT JOIN UserTopPostsRanked UTPR ON UAS.UserId = UTPR.OwnerUserId AND UTPR.UserSpecificPostRank = 1
LEFT JOIN UserPostTagPreference UPTP ON UAS.UserId = UPTP.UserId AND UPTP.TagRank = 1
LEFT JOIN TagUsageMetrics TUM ON UPTP.TagName = TUM.TagName
LEFT JOIN UserOverallPostStats UPS ON UAS.UserId = UPS.UserId
WHERE UAS.Reputation > 100 -- Filter out very low-reputation users for meaningful analysis
  AND UAS.TotalPosts > 0
  -- Use a NOT EXISTS subquery to filter out users who have not posted any questions containing "performance" keywords
  AND EXISTS (
      SELECT 1 FROM PostContentDetailedAnalysis PCDA_Check
      WHERE PCDA_Check.OwnerUserId = UAS.UserId
        AND PCDA_Check.PostTypeId = 1
        AND PCDA_Check.ContainsPerfKeywords = 1
  )

UNION ALL

-- Second branch: Identifies "high-impact" questions that are unanswered or poorly answered, focusing on performance-related topics
SELECT
    0 AS UserId, -- Placeholder for community-level insights
    'Community Focus' AS DisplayName,
    0 AS Reputation,
    1 AS TotalQuestions,
    0 AS TotalAnswers,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    MAX(PCDA.PostCreationDate) AS LastKnownActivity,
    AVG(PCDA.PostScore) AS UserOverallAvgPostScore,
    0 AS TotalPostEditsByOwner,
    COALESCE(PCDA.Title, 'N/A') AS TopPostTitle,
    PCDA.PostScore AS TopPostScore,
    PCDA.ViewCount AS TopPostViews,
    NULL AS PrimaryTagForQuestions,
    NULL AS PrimaryTagAvgPostScore,
    NULL AS PrimaryTagAcceptedAnswerRate,
    AVG(PCDA.BodyLength) AS AvgQuestionBodyLength,
    NULL AS AvgAnswerBodyLength,
    0 AS BestAnswerScoreToPopularQuestion,
    NULL AS FirstGoldBadgeDate,
    0 AS UserEngagementScore,
    0 AS OverallUserActivityRank,
    0 AS HighQualityPerfQuestionsCount,
    0 AS AvgScorePerYear,
    'Unanswered High-Impact Question' AS UserCategory
FROM PostContentDetailedAnalysis PCDA
WHERE PCDA.PostTypeId = 1 -- Only questions
  AND PCDA.ViewCount > 10000 -- Very popular
  AND PCDA.AnswerCount < 3 -- Few answers
  AND PCDA.AcceptedAnswerId IS NULL -- No accepted answer
  AND PCDA.ClosedDate IS NULL -- Still open
  AND PCDA.ContainsPerfKeywords = 1 -- Focus on performance related
  AND PCDA.PostCreationDate >= NOW() - INTERVAL '2 years' -- Relatively recent questions
GROUP BY
    PCDA.PostId, PCDA.Title, PCDA.PostScore, PCDA.ViewCount -- Group by post for distinct questions
HAVING COUNT(PCDA.PostId) = 1 -- Ensure each question is a distinct row
ORDER BY
    UserEngagementScore DESC,
    Reputation DESC,
    TopPostViews DESC,
    LastKnownActivity DESC NULLS LAST;
