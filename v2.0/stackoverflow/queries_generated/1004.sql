-- {"query": "1004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3509} 

WITH UserEngagement AS (
    -- Summarizes user activity, including post counts, vote counts (given), and badge counts.
    -- Uses LEFT JOIN for optional data (posts, badges, votes, comments) and COALESCE for NULL handling.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        MIN(P.CreationDate) AS FirstPostDate,
        MIN(B.Date) AS FirstBadgeDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation > 100 -- Filter out very inactive users
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailedMetrics AS (
    -- Provides detailed metrics for Posts, including edit history, comment analysis, and link types.
    -- Features correlated subqueries for dynamic calculations and CASE statements for conditional logic.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.ParentId, -- Added for linking answers to questions
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId_C,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS EditCount, -- Title, Body, Tags edits
        (SELECT AVG(COALESCE(C.Score, 0)) FROM Comments C WHERE C.PostId = P.Id) AS AverageCommentScore,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.UserId IS NOT NULL AND PH.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorCount, -- Only count users who made actual edits
        CASE WHEN EXISTS (SELECT 1 FROM PostLinks PL WHERE (PL.PostId = P.Id OR PL.RelatedPostId = P.Id) AND PL.LinkTypeId = 3) THEN TRUE ELSE FALSE END AS HasAnyDuplicateLink, -- Checks if post is source OR target of a duplicate link
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        CASE WHEN P.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        -- Detects posts that were closed and then reopened using PostHistoryTypes 10 (Closed) and 11 (Reopened)
        CASE WHEN (SELECT COUNT(PH_CR.Id) FROM PostHistory PH_CR WHERE PH_CR.PostId = P.Id AND PH_CR.PostHistoryTypeId = 10) > 0 AND
                  (SELECT COUNT(PH_OR.Id) FROM PostHistory PH_OR WHERE PH_OR.PostId = P.Id AND PH_OR.PostHistoryTypeId = 11) > 0
             THEN TRUE ELSE FALSE END AS WasClosedAndReopened,
        -- Calculates time to first *actual* edit in hours, allowing for NULL if no edits occurred
        EXTRACT(EPOCH FROM (
            (SELECT MIN(PH_EDIT.CreationDate) FROM PostHistory PH_EDIT WHERE PH_EDIT.PostId = P.Id AND PH_EDIT.PostHistoryTypeId IN (4,5,6))
            - P.CreationDate
        )) / 3600.0 AS TimeToFirstEditHours,
        COALESCE(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '') AS CleanTagsString -- Cleans tags string by removing angle brackets, handling NULLs
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND P.CreationDate BETWEEN '2018-01-01' AND '2023-12-31' -- Specific date range for benchmarking
    AND P.ViewCount IS NOT NULL -- Exclude certain post types without meaningful view counts
),
TagAggregates AS (
    -- Aggregates performance metrics per tag, using string manipulation and UNNEST.
    SELECT
        TRIM(UNNEST(string_to_array(PDM.CleanTagsString, '><'))) AS TagName,
        COUNT(DISTINCT PDM.PostId) AS TaggedPostCount,
        SUM(PDM.PostScore) AS TotalTagScore,
        AVG(PDM.PostScore) AS AvgTagScore,
        AVG(PDM.ViewCount) AS AvgTagViewCount,
        MIN(PDM.PostCreationDate) AS FirstTagPostDate
    FROM PostDetailedMetrics PDM
    WHERE PDM.CleanTagsString IS NOT NULL AND PDM.CleanTagsString != ''
    GROUP BY TRIM(UNNEST(string_to_array(PDM.CleanTagsString, '><')))
    HAVING COUNT(DISTINCT PDM.PostId) > 100 -- Focus on more popular tags
),
RankedTagPerformance AS (
    -- Ranks tags based on their aggregated scores and view counts using window functions.
    SELECT
        TagName,
        TaggedPostCount,
        TotalTagScore,
        AvgTagScore,
        AvgTagViewCount,
        FirstTagPostDate,
        RANK() OVER (ORDER BY TotalTagScore DESC, TaggedPostCount DESC) AS RankByTotalScore, -- Rank based on total score and post count
        NTILE(10) OVER (ORDER BY AvgTagViewCount DESC) AS ViewCountDecile -- Categorize into deciles by average view count
    FROM TagAggregates
),
PostTagRankSelector AS (
    -- Selects the highest ranked tag for each post. Uses ROW_NUMBER() over a join with RankedTagPerformance.
    SELECT
        PostId,
        TagName,
        RankByTotalScore,
        ViewCountDecile,
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY RankByTotalScore ASC, TaggedPostCount DESC) AS rn
    FROM PostDetailedMetrics
    CROSS JOIN LATERAL (SELECT TRIM(UNNEST(string_to_array(CleanTagsString, '><'))) AS TagName) AS T_Tags -- Expands tags into rows
    INNER JOIN RankedTagPerformance RTP ON T_Tags.TagName = RTP.TagName
    WHERE T_Tags.TagName IS NOT NULL AND T_Tags.TagName != ''
),
FinalAnalysis_Questions AS (
    -- Analyzes questions by joining user engagement, post metrics, and ranked tag data.
    -- Includes complex expressions, conditional logic, and a window function for sequential analysis.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        PDM.PostId,
        PDM.PostCreationDate,
        PDM.PostScore,
        PDM.ViewCount,
        PDM.Title,
        PDM.Tags,
        PDM.EditCount,
        PDM.AverageCommentScore,
        PDM.UniqueEditorCount,
        PDM.HasAnyDuplicateLink AS HasDuplicateLink,
        PDM.HasAcceptedAnswer,
        PDM.IsClosed,
        PDM.WasClosedAndReopened,
        PDM.TimeToFirstEditHours,
        COALESCE(PDM.FavoriteCount, 0) AS FavoriteCount_C,
        PTRS.TagName AS PrimaryTagName, -- Highest ranked tag for the question
        PTRS.RankByTotalScore,
        PTRS.ViewCountDecile,
        -- Complex engagement ratio calculation, handling division by zero with GREATEST
        (PDM.PostScore * (1 + COALESCE(PDM.FavoriteCount, 0) / 10.0)) / (GREATEST(PDM.ViewCount, 1) + 1.0) AS EngagementRatio,
        AGE(NOW(), PDM.PostCreationDate) AS PostAge, -- Age of the post
        CASE
            WHEN PDM.PostScore >= 50 AND PDM.HasAcceptedAnswer THEN 'High_Impact_Solved'
            WHEN PDM.PostScore >= 20 AND PDM.HasAcceptedAnswer IS FALSE AND PDM.IsClosed IS FALSE THEN 'High_Impact_Unsolved'
            WHEN PDM.WasClosedAndReopened THEN 'Controversial_Resolved'
            WHEN PDM.IsClosed THEN 'Closed_Question'
            ELSE 'Standard_Question'
        END AS QuestionCategory,
        -- Calculates the previous post date for the same user, demonstrating LAG window function
        LAG(PDM.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY UE.UserId ORDER BY PDM.PostCreationDate) AS PreviousPostDate
    FROM UserEngagement UE
    INNER JOIN PostDetailedMetrics PDM ON UE.UserId = PDM.OwnerUserId
    LEFT JOIN PostTagRankSelector PTRS ON PDM.PostId = PTRS.PostId AND PTRS.rn = 1
    WHERE PDM.PostTypeId = 1 -- Only questions
    AND PDM.ViewCount > 1000 -- Filter for popular questions
    AND PDM.PostScore > 5 -- Filter for moderately scored questions
    -- Complex predicate for title/tag content, demonstrating string matching
    AND (PDM.Title LIKE '%SQL%' OR PDM.Title LIKE '%database%' OR PDM.Tags LIKE '%<sql>%' OR PDM.Tags LIKE '%<database>%')
),
FinalAnalysis_Answers AS (
    -- Analyzes answers, linking them to their parent questions for context.
    -- Similar structure to FinalAnalysis_Questions but adapted for answer-specific metrics.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        PDM.PostId,
        PDM.PostCreationDate,
        PDM.PostScore,
        ParentPost.ViewCount AS ParentQuestionViewCount, -- Use parent question's view count
        ParentPost.Title AS ParentQuestionTitle,
        ParentPost.Tags AS ParentQuestionTags, -- Use parent question's tags
        PDM.EditCount,
        PDM.AverageCommentScore,
        PDM.UniqueEditorCount,
        PDM.HasAnyDuplicateLink AS HasDuplicateLink,
        PDM.HasAcceptedAnswer, -- For answers, indicates if this answer was accepted
        PDM.IsClosed, -- Status of the answer itself (rarely directly closed, often inherits from parent)
        PDM.WasClosedAndReopened, -- Same as above
        PDM.TimeToFirstEditHours,
        COALESCE(PDM.FavoriteCount, 0) AS FavoriteCount_C, -- Answers rarely have favorites
        PTRS.TagName AS PrimaryTagName, -- Highest ranked tag from the parent question
        PTRS.RankByTotalScore,
        PTRS.ViewCountDecile,
        -- Simplified impact score for answers
        (PDM.PostScore * (1 + COALESCE(PDM.FavoriteCount, 0) / 5.0)) AS AnswerImpactScore,
        AGE(NOW(), PDM.PostCreationDate) AS PostAge,
        CASE
            WHEN PDM.PostScore >= 30 AND PDM.HasAcceptedAnswer THEN 'Top_Accepted_Answer'
            WHEN PDM.PostScore >= 10 AND PDM.HasAcceptedAnswer IS FALSE THEN 'High_Scored_Answer'
            ELSE 'Standard_Answer'
        END AS AnswerCategory,
        LAG(PDM.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY UE.UserId ORDER BY PDM.PostCreationDate) AS PreviousPostDate
    FROM UserEngagement UE
    INNER JOIN PostDetailedMetrics PDM ON UE.UserId = PDM.OwnerUserId
    INNER JOIN Posts ParentPost ON PDM.ParentId = ParentPost.Id AND PDM.PostTypeId = 2 -- Link answers to their parent questions
    LEFT JOIN PostTagRankSelector PTRS ON ParentPost.Id = PTRS.PostId AND PTRS.rn = 1 -- Link answers to parent question's tags
    WHERE PDM.PostTypeId = 2 -- Only answers
    AND PDM.PostScore > 2 -- Filter for moderately scored answers
    -- String matching against parent question's title/tags
    AND (ParentPost.Title LIKE '%SQL%' OR ParentPost.Title LIKE '%database%' OR ParentPost.Tags LIKE '%<sql>%' OR ParentPost.Tags LIKE '%<database>%')
)
-- Final result set combines question and answer analysis using UNION ALL
SELECT
    'Question' AS PostTypeCategory,
    FQ.UserId,
    FQ.DisplayName,
    FQ.Reputation,
    FQ.PostId,
    FQ.PostCreationDate,
    FQ.PostScore,
    FQ.ViewCount,
    FQ.Title,
    FQ.Tags,
    FQ.EditCount,
    FQ.AverageCommentScore,
    FQ.UniqueEditorCount,
    FQ.HasDuplicateLink,
    FQ.HasAcceptedAnswer,
    FQ.IsClosed,
    FQ.WasClosedAndReopened,
    FQ.TimeToFirstEditHours,
    FQ.FavoriteCount_C,
    FQ.PrimaryTagName,
    FQ.RankByTotalScore,
    FQ.ViewCountDecile,
    FQ.EngagementRatio AS DerivedScore, -- Renamed for consistency across UNION
    FQ.PostAge,
    FQ.QuestionCategory AS PostSpecificCategory,
    FQ.PreviousPostDate,
    NULL AS ParentPostTitle, -- Explicitly NULL for questions
    NULL AS ParentPostTags, -- Explicitly NULL for questions
    FQ.EngagementRatio AS GeneralPerformanceMetric -- Metric for general performance/impact
FROM FinalAnalysis_Questions FQ

UNION ALL

SELECT
    'Answer' AS PostTypeCategory,
    FA.UserId,
    FA.DisplayName,
    FA.Reputation,
    FA.PostId,
    FA.PostCreationDate,
    FA.PostScore,
    FA.ParentQuestionViewCount AS ViewCount, -- Map to common column name
    FA.ParentQuestionTitle AS Title, -- Map to common column name
    FA.ParentQuestionTags AS Tags, -- Map to common column name
    FA.EditCount,
    FA.AverageCommentScore,
    FA.UniqueEditorCount,
    FA.HasDuplicateLink,
    FA.HasAcceptedAnswer,
    FA.IsClosed,