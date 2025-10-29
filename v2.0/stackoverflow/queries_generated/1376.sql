-- {"query": "1376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3095} 

WITH QuestionerMetrics AS (
    -- Aggregates statistics for users who primarily ask questions
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS QuestionsAsked,
        SUM(COALESCE(P.Score, 0)) AS TotalQuestionScore,
        AVG(P.ViewCount) AS AvgQuestionViews,
        COUNT(P.AcceptedAnswerId) AS QuestionsWithAcceptedAnswers,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalQuestionFavorites
    FROM Posts P
    WHERE P.PostTypeId = 1 -- PostType 1 corresponds to 'Question'
      AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
AnswererMetrics AS (
    -- Aggregates statistics for users who primarily provide answers
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS AnswersProvided,
        SUM(COALESCE(P.Score, 0)) AS TotalAnswerScore,
        AVG(LENGTH(P.Body)) AS AvgAnswerBodyLength, -- String expression: Average length of answer bodies
        COUNT(CASE WHEN PARENT.AcceptedAnswerId = P.Id THEN 1 END) AS AcceptedAnswersGiven
    FROM Posts P
    INNER JOIN Posts PARENT ON P.ParentId = PARENT.Id -- Join to relate answers to their parent questions
    WHERE P.PostTypeId = 2 -- PostType 2 corresponds to 'Answer'
      AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserActivitySummary AS (
    -- Provides a general overview of user activity including posts and creation dates
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        SUM(COALESCE(P.Score, 0)) AS TotalCombinedPostScore,
        MAX(P.LastActivityDate) AS LastUserActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.Reputation, U.CreationDate
),
PostEditActivity AS (
    -- Analyzes post editing activity, including time differences between edits
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEdits, -- Edit Title, Edit Body, Edit Tags
        MAX(PH.CreationDate) AS LastEditDate,
        MIN(PH.CreationDate) AS FirstEditDate,
        -- Window function: Calculate the maximum time interval between consecutive edits for a post
        MAX(LEAD(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) - PH.CreationDate) AS MaxEditInterval
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PH.PostId
),
PostClosureAnalysis AS (
    -- Identifies posts that were closed, especially those closed as duplicates, and extracts related original questions
    SELECT
        PH.PostId,
        P.OwnerUserId AS ClosedPostOwnerId,
        PH.CreationDate AS ClosedDate,
        -- NULL logic: COALESCE to handle cases where CloseReasonName might be unknown
        COALESCE(CR.Name, 'Unknown Reason') AS CloseReasonName,
        CAST(SUBSTRING(PH.Comment FROM '[0-9]+') AS smallint) AS CloseReasonId,
        -- Correlated subquery: Extract OriginalQuestionIds from JSON string in the 'Text' field (PostgreSQL specific)
        CASE WHEN PH.Text LIKE '%OriginalQuestionIds%'
             THEN (SELECT array_agg(CAST(json_array_elements_text(obj->'OriginalQuestionIds') AS int))
                   FROM json_each(PH.Text::json) AS j(key, obj)
                   WHERE j.key = 'OriginalQuestionIds'
                  )
             ELSE NULL END AS OriginalQuestionIdsArray
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    LEFT JOIN CloseReasonTypes CR ON CAST(SUBSTRING(PH.Comment FROM '[0-9]+') AS smallint) = CR.Id
    WHERE PH.PostHistoryTypeId = 10 -- PostType 10 corresponds to 'Post Closed'
      AND PH.Comment IS NOT NULL
),
UserTagPerformance AS (
    -- Analyzes a user's activity and performance for specific tags
    SELECT
        P.OwnerUserId AS UserId,
        -- String expression: Extract individual tags from the 'Tags' string
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS PostsInTag,
        SUM(COALESCE(P.Score, 0)) AS ScoreInTag,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersInTag
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.Tags IS NOT NULL
      AND P.PostTypeId = 1 -- Only questions have tags and accepted answers directly
    GROUP BY P.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))
),
RankedUserTagPerformance AS (
    -- Ranks the tags for each user based on their performance (score and accepted answers)
    SELECT
        UserId,
        TagName,
        PostsInTag,
        ScoreInTag,
        AcceptedAnswersInTag,
        -- Window function: Rank tags for each user
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY ScoreInTag DESC, AcceptedAnswersInTag DESC, PostsInTag DESC) AS TagRank
    FROM UserTagPerformance
),
UserCommentActivity AS (
    -- Aggregates comment-related activity for users
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalComments,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
CombinedUserMetrics AS (
    -- Consolidates all aggregated metrics for each user into a single view
    SELECT
        UAS.UserId,
        UAS.Reputation,
        UAS.UserCreationDate,
        UAS.TotalPosts,
        UAS.TotalCombinedPostScore,
        UAS.LastUserActivityDate,
        COALESCE(QM.QuestionsAsked, 0) AS QuestionsAsked,
        COALESCE(QM.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(QM.AvgQuestionViews, 0.0) AS AvgQuestionViews,
        COALESCE(QM.QuestionsWithAcceptedAnswers, 0) AS QuestionsWithAcceptedAnswers,
        COALESCE(QM.TotalQuestionFavorites, 0) AS TotalQuestionFavorites,
        COALESCE(AM.AnswersProvided, 0) AS AnswersProvided,
        COALESCE(AM.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(AM.AvgAnswerBodyLength, 0.0) AS AvgAnswerBodyLength,
        COALESCE(AM.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven,
        COALESCE(UCA.TotalComments, 0) AS TotalComments,
        COALESCE(UCA.TotalCommentScore, 0) AS TotalCommentScore,
        -- NULL logic: Default to user creation date if no comment activity
        COALESCE(UCA.LastCommentDate, UAS.UserCreationDate) AS LastCommentActivityDate,
        -- Join Posts with PostEditActivity and PostClosureAnalysis on the fly for aggregated counts
        SUM(COALESCE(PEA.TotalEdits, 0)) AS TotalEditsOnOwnedPosts,
        COUNT(DISTINCT PCA.PostId) AS TotalClosedPostsOwned,
        COUNT(DISTINCT CASE WHEN PCA.CloseReasonId IN (1, 101) THEN PCA.PostId END) AS TotalDuplicateClosedPostsOwned, -- Close reason 1='Exact Duplicate', 101='Duplicate'
        SUM(CASE WHEN PCA.OriginalQuestionIdsArray IS NOT NULL THEN array_length(PCA.OriginalQuestionIdsArray, 1) ELSE 0 END) AS TotalDuplicateLinksFound,
        -- Complicated calculation: A custom engagement score
        (COALESCE(QM.QuestionsAsked, 0) * 0.5 + COALESCE(AM.AnswersProvided, 0) * 0.7 + COALESCE(UCA.TotalComments, 0) * 0.3) AS EngagementScore,
        AVG(PEA.MaxEditInterval) AS AvgMaxEditIntervalForOwnedPosts
    FROM UserActivitySummary UAS
    LEFT JOIN QuestionerMetrics QM ON UAS.UserId = QM.UserId
    LEFT JOIN AnswererMetrics AM ON UAS.UserId = AM.UserId
    LEFT JOIN UserCommentActivity UCA ON UAS.UserId = UCA.UserId
    LEFT JOIN Posts P ON UAS.UserId = P.OwnerUserId -- Re-join to link edits/closures to user owned posts
    LEFT JOIN PostEditActivity PEA ON P.Id = PEA.PostId
    LEFT JOIN PostClosureAnalysis PCA ON P.Id = PCA.PostId
    GROUP BY
        UAS.UserId, UAS.Reputation, UAS.UserCreationDate, UAS.TotalPosts, UAS.TotalCombinedPostScore,
        UAS.LastUserActivityDate, QM.QuestionsAsked, QM.TotalQuestionScore, QM.AvgQuestionViews,
        QM.QuestionsWithAcceptedAnswers, QM.TotalQuestionFavorites, AM.AnswersProvided, AM.TotalAnswerScore,
        AM.AvgAnswerBodyLength, AM.AcceptedAnswersGiven, UCA.TotalComments, UCA.TotalCommentScore, UCA.LastCommentDate
)
-- Final selection of influential users based on a complex composite score
SELECT
    CUM.UserId,
    U.DisplayName,
    U.ProfileImageUrl,
    U.Reputation,
    CUM.TotalPosts,
    CUM.TotalCombinedPostScore,
    CUM.QuestionsAsked,
    CUM.AnswersProvided,
    CUM.AcceptedAnswersGiven,
    CUM.TotalEditsOnOwnedPosts,
    CUM.TotalClosedPostsOwned,
    CUM.TotalDuplicateClosedPostsOwned,
    CUM.EngagementScore,
    RUTP.TagName AS TopContributingTag,
    RUTP.ScoreInTag AS TopTagScore,
    RUTP.AcceptedAnswersInTag AS TopTagAcceptedAnswers,
    -- Complicated calculation: A comprehensive composite influence score
    (
        (CUM.Reputation * 0.05) +
        (CUM.TotalCombinedPostScore * 0.3) +
        (CUM.AcceptedAnswersGiven * 10) +
        (CUM.TotalEditsOnOwnedPosts * 0.1) +
        (CUM.EngagementScore * 0.8) -
        (CUM.TotalDuplicateClosedPostsOwned * 20) + -- Heavy penalty for posts closed as duplicates
        COALESCE(RUTP.ScoreInTag, 0) * 0.02 + -- Bonus from top tag performance
        (COALESCE(CUM.AvgQuestionViews, 0) * 0.005) +
        (CASE WHEN U.WebsiteUrl IS NOT NULL THEN 50 ELSE 0 END) + -- Bonus for having a website
        (CASE WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 200 THEN 25 ELSE 0 END) + -- Bonus for a detailed 'About Me' section
        (CASE WHEN CUM.AvgMaxEditIntervalForOwnedPosts IS NOT NULL AND CUM.AvgMaxEditIntervalForOwnedPosts < INTERVAL '1 hour' THEN 10 ELSE 0 END) -- Bonus for users with rapid editing activity
    ) AS FinalInfluenceScore,
    (U.LastAccessDate - U.CreationDate) AS UserLifespan, -- Date/time expression: Calculate user account age
    COALESCE(U.Location, 'Earth') AS UserLocation, -- NULL logic: Default location
    UPPER(SUBSTRING(COALESCE(U.Location, 'N/A'), 1, 3)) AS LocationPrefix_Upper, -- String expression: Uppercase first 3 chars of location
    LOWER(U.DisplayName) LIKE '%dev%' AS IsDeveloperKeywordInName -- String expression: Check for 'dev' in lowercased display name
FROM CombinedUserMetrics CUM
INNER JOIN Users U ON CUM.UserId = U.Id
LEFT JOIN RankedUserTagPerformance RUTP ON CUM.UserId = RUTP.UserId AND RUTP.TagRank = 1
WHERE U.Reputation > 2000 -- Complicated predicate: Filter for reasonably influential users
  AND CUM.TotalPosts > 10
  AND CUM.TotalCombinedPostScore > 50
  AND CUM.UserCreationDate BETWEEN '2010-01-01' AND '2022-12-31' -- Filter by user creation date range
  AND NOT (U.AboutMe IS NULL AND U.WebsiteUrl IS NULL) -- Complicated predicate/NULL logic: Exclude users with no bio and no website
ORDER BY FinalInfluenceScore DESC, U.Reputation DESC, CUM.LastUserActivityDate DESC
LIMIT 500;
