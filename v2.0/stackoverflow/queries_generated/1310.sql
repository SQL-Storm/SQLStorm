-- {"query": "1310.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4091} 

WITH UserStats AS (
    -- CTE 1: Aggregates various statistics for each user, including post counts, comment counts, badge counts, and reputation-related metrics.
    -- Uses LEFT JOIN to ensure all users are included, even those without posts or comments.
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        -- Complex calculation: User's age in days
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60*60*24) AS UserAgeDays,
        -- Complex calculation: Days since user's last access, handling potential NULLs if NOW() is before LastAccessDate
        COALESCE(EXTRACT(EPOCH FROM (NOW() - U.LastAccessDate)) / (60*60*24), 0) AS DaysSinceLastAccess,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN V_Rec.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V_Rec.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    -- Join with Votes to count votes received on posts owned by the user
    LEFT JOIN Votes AS V_Rec ON P.Id = V_Rec.PostId AND V_Rec.VoteTypeId IN (2, 3)
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostCoreMetrics AS (
    -- CTE 2: Extracts core metrics and details for Posts, specifically focusing on Questions (PostTypeId = 1) and Answers (PostTypeId = 2).
    -- Includes string manipulation and NULL logic for display.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Body,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        -- NULL Logic: Boolean flag for accepted answer presence
        (P.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
        -- NULL Logic: Boolean flag for post closure, defaulting to FALSE if ClosedDate is NULL
        COALESCE(P.ClosedDate IS NOT NULL, FALSE) AS IsClosed,
        -- Complex calculation: Post's age in days
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60*60*24) AS PostAgeDays,
        -- Complex calculation: Time since last activity in hours
        EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / (60*60) AS TimeSinceLastActivityHours,
        -- String expression: Parses tags from the string format into an array, handling NULL tags
        COALESCE(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), ARRAY[]::VARCHAR[]) AS TagArray,
        -- String expression: Creates a shortened title preview
        CASE
            WHEN LENGTH(P.Title) > 100 THEN LEFT(P.Title, 97) || '...'
            ELSE P.Title
        END AS ShortTitlePreview
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Filter to Questions and Answers
    AND P.OwnerUserId IS NOT NULL -- Exclude community owned posts for this specific analysis
),
PostEditAnalysis AS (
    -- CTE 3: Analyzes post edit history, calculating total edits, unique editors, and average time between edits.
    -- Uses a subquery with a window function for `LAG` to compute time differences between consecutive edits.
    SELECT
        PostId,
        COUNT(Id) AS TotalEditHistoryEntries,
        COUNT(DISTINCT UserId) AS UniqueEditors,
        MAX(CreationDate) AS LatestEditDate,
        MIN(CreationDate) AS EarliestEditDate,
        -- Window function: Calculate average time between *consecutive* edits by the *same user* on the same post
        AVG(CASE WHEN prev_user_id = UserId THEN edit_diff_seconds ELSE NULL END) / (60*60) AS AvgTimeBetweenUserEditsHours,
        -- Complicated predicate: Determines if there was a rapid self-edit (within 5 minutes) shortly after a previous edit
        MAX(CASE WHEN edit_diff_seconds IS NOT NULL AND edit_diff_seconds < 300 AND prev_user_id = UserId THEN 1 ELSE 0 END) AS HasRapidSelfEdit
    FROM (
        SELECT
            PH.PostId,
            PH.Id,
            PH.UserId,
            PH.CreationDate,
            LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS prev_edit_date,
            LAG(PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS prev_user_id,
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) AS edit_diff_seconds
        FROM PostHistory AS PH
        WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    ) AS EditDifferences
    GROUP BY PostId
),
QuestionAnswerContext AS (
    -- CTE 4: Provides context for questions (accepted answer details) and answers (parent question details).
    -- Utilizes correlated subqueries for efficient lookup of related post data.
    SELECT
        PCM.PostId,
        PCM.PostTypeId,
        PCM.AcceptedAnswerId,
        PCM.ParentId,
        -- Correlated subquery: Get score of the accepted answer
        (SELECT A.Score FROM Posts AS A WHERE A.Id = PCM.AcceptedAnswerId) AS AcceptedAnswerScore,
        -- Correlated subquery: Get reputation of the accepted answer's owner
        (SELECT UA.Reputation FROM Posts AS A JOIN Users AS UA ON A.OwnerUserId = UA.Id WHERE A.Id = PCM.AcceptedAnswerId) AS AcceptedAnswerOwnerReputation,
        -- Correlated subquery: Get score of the parent question for answers
        (SELECT Q.Score FROM Posts AS Q WHERE Q.Id = PCM.ParentId) AS ParentQuestionScore,
        -- Correlated subquery: Get view count of the parent question for answers
        (SELECT Q.ViewCount FROM Posts AS Q WHERE Q.Id = PCM.ParentId) AS ParentQuestionViewCount,
        -- Complicated predicate: Checks if the accepted answer is by a different user than the question owner
        (SELECT Q.OwnerUserId <> A.OwnerUserId
         FROM Posts AS Q JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id
         WHERE Q.Id = PCM.PostId AND Q.AcceptedAnswerId IS NOT NULL
        ) AS IsAcceptedAnswerByDifferentUser
    FROM PostCoreMetrics AS PCM
),
WeightedTagMetrics AS (
    -- CTE 5: Calculates weighted scores and ranks for tags based on average post scores, view counts, and number of posts.
    -- Uses CROSS JOIN LATERAL with UNNEST to process tags from array.
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedPostCount,
        AVG(Score) AS AvgScoreForTag,
        AVG(ViewCount) AS AvgViewCountForTag,
        AVG(CommentCount) AS AvgCommentCountForTag,
        -- Complicated calculation: Weighted Tag Score using a logarithmic scale for post count
        (AVG(Score) * 0.7 + AVG(ViewCount) * 0.3) * LOG(COUNT(DISTINCT PostId) + 1) AS WeightedTagScore,
        -- Window function: Ranks tags based on their calculated weighted score
        RANK() OVER (ORDER BY (AVG(Score) * 0.7 + AVG(ViewCount) * 0.3) * LOG(COUNT(DISTINCT PostId) + 1) DESC) AS TagRankByWeightedScore
    FROM PostCoreMetrics
    CROSS JOIN LATERAL UNNEST(TagArray) AS TagName
    WHERE TagArray IS NOT NULL AND array_length(TagArray, 1) > 0
    GROUP BY TagName
),
HighImpactPosts AS (
    -- CTE 6: Combines all previous CTEs to create a comprehensive view of high-impact posts.
    -- Includes composite engagement indices, owner details, and applies initial filtering.
    SELECT
        PCM.PostId,
        PCM.OwnerUserId,
        PCM.PostTypeName,
        PCM.ShortTitlePreview,
        PCM.Score,
        PCM.ViewCount,
        PCM.CommentCount,
        US.Reputation AS OwnerReputation,
        US.TotalPostsOwned,
        US.DaysSinceLastAccess,
        PEA.TotalEditHistoryEntries,
        PEA.UniqueEditors,
        PEA.AvgTimeBetweenUserEditsHours,
        PEA.HasRapidSelfEdit,
        QAC.AcceptedAnswerScore,
        QAC.AcceptedAnswerOwnerReputation,
        QAC.ParentQuestionScore,
        QAC.ParentQuestionViewCount,
        QAC.IsAcceptedAnswerByDifferentUser,
        -- Aggregated tag influence: Sum of weighted scores of all tags associated with the post
        COALESCE(SUM(WTM.WeightedTagScore), 0.0) AS TotalWeightedTagInfluence,
        COUNT(DISTINCT WTM.TagName) AS NumTagsOnPost,
        -- Complicated calculation: A composite engagement index for the post
        (PCM.Score * 0.5 + PCM.ViewCount * 0.3 + PCM.CommentCount * 0.2) AS PostEngagementIndex,
        -- NULL Logic: Use COALESCE to provide a default display name for community posts (though filtered out earlier for OwnerUserId IS NOT NULL)
        COALESCE(US.UserDisplayName, 'Community User') AS EffectiveOwnerDisplayName,
        -- Window function: Ranks posts by their engagement index within each post type
        RANK() OVER (PARTITION BY PCM.PostTypeId ORDER BY (PCM.Score * 0.5 + PCM.ViewCount * 0.3 + PCM.CommentCount * 0.2) DESC) AS RankWithinPostType,
        -- Window function: Calculates the average engagement index for all posts by the same owner
        AVG(PCM.Score * 0.5 + PCM.ViewCount * 0.3 + PCM.CommentCount * 0.2) OVER (PARTITION BY PCM.OwnerUserId) AS AvgOwnerPostEngagement
    FROM PostCoreMetrics AS PCM
    INNER JOIN UserStats AS US ON PCM.OwnerUserId = US.UserId
    LEFT JOIN PostEditAnalysis AS PEA ON PCM.PostId = PEA.PostId
    LEFT JOIN QuestionAnswerContext AS QAC ON PCM.PostId = QAC.PostId
    -- Use LATERAL UNNEST to join posts with their individual tags for weighted tag metrics
    LEFT JOIN LATERAL UNNEST(PCM.TagArray) AS PostTag ON TRUE
    LEFT JOIN WeightedTagMetrics AS WTM ON PostTag = WTM.TagName
    GROUP BY
        PCM.PostId, PCM.OwnerUserId, PCM.PostTypeName, PCM.ShortTitlePreview, PCM.Score, PCM.ViewCount, PCM.CommentCount,
        US.Reputation, US.TotalPostsOwned, US.DaysSinceLastAccess, US.UserDisplayName,
        PEA.TotalEditHistoryEntries, PEA.UniqueEditors, PEA.AvgTimeBetweenUserEditsHours, PEA.HasRapidSelfEdit,
        QAC.AcceptedAnswerScore, QAC.AcceptedAnswerOwnerReputation, QAC.ParentQuestionScore, QAC.ParentQuestionViewCount, QAC.IsAcceptedAnswerByDifferentUser
    HAVING (PCM.Score > 100 OR PCM.ViewCount > 5000) -- Predicate: Filter for sufficiently engaged posts
    AND US.Reputation > 500 -- Predicate: Filter for users with at least some reputation
)
-- Main query: Uses a UNION ALL set operator to combine two different analytical perspectives on high-impact posts.
SELECT
    'Top Engaged Questions' AS AnalysisCategory,
    HIP.PostId,
    HIP.PostTypeName,
    HIP.ShortTitlePreview,
    HIP.Score,
    HIP.ViewCount,
    HIP.CommentCount,
    HIP.OwnerReputation,
    HIP.EffectiveOwnerDisplayName,
    HIP.TotalWeightedTagInfluence,
    HIP.NumTagsOnPost,
    HIP.PostEngagementIndex,
    HIP.RankWithinPostType,
    HIP.AvgOwnerPostEngagement,
    HIP.TotalEditHistoryEntries,
    HIP.UniqueEditors,
    HIP.HasRapidSelfEdit,
    HIP.IsAcceptedAnswerByDifferentUser,
    -- Complicated calculation with NULLIF for division by zero and COALESCE for default value
    COALESCE(
        NULLIF(HIP.AcceptedAnswerOwnerReputation, 0) / NULLIF(HIP.OwnerReputation, 0),
        0.0
    ) AS AcceptedAnswerOwnerReputationRatio,
    -- Correlated subquery: Counts legacy favorite votes for the post
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = HIP.PostId AND V.VoteTypeId = 5) AS TotalFavoritesLegacy
FROM HighImpactPosts AS HIP
WHERE HIP.PostTypeName = 'Question'
AND HIP.PostEngagementIndex > 500 -- Predicate: High engagement index
AND HIP.RankWithinPostType <= 100 -- Predicate: Among the top 100 questions by engagement
AND HIP.DaysSinceLastAccess < 365 -- Predicate: Owners active in the last year
AND HIP.TotalWeightedTagInfluence > 1000 -- Predicate: Posts with strong tag influence
AND (HIP.UniqueEditors > 1 OR HIP.HasRapidSelfEdit = 1) -- Predicate: Edited by multiple people or rapidly self-edited
-- Predicate with NOT EXISTS: Exclude posts that are duplicates
AND NOT EXISTS (
    SELECT 1 FROM PostLinks PL
    WHERE PL.PostId = HIP.PostId
    AND PL.LinkTypeId = 3
)
-- String expression predicate: Title contains 'data' (case-sensitive) or 'sql' (case-insensitive)
AND (HIP.ShortTitlePreview LIKE '%data%' OR HIP.ShortTitlePreview ILIKE '%sql%')
-- NULL logic predicates: Ensure key metrics are not NULL
AND HIP.AcceptedAnswerScore IS NOT NULL
AND HIP.AvgTimeBetweenUserEditsHours IS NOT NULL
AND HIP.AcceptedAnswerOwnerReputation IS NOT NULL
AND HIP.OwnerReputation IS NOT NULL
-- Complicated predicate: Exclude highly viewed but heavily downvoted posts
AND NOT (HIP.Score < -10 AND HIP.ViewCount > 10000)

UNION ALL

SELECT
    'Highly Scored Answers by Active Users' AS AnalysisCategory,
    HIP.PostId,
    HIP.PostTypeName,
    HIP.ShortTitlePreview,
    HIP.Score,
    HIP.ViewCount,
    HIP.CommentCount,
    HIP.OwnerReputation,
    HIP.EffectiveOwnerDisplayName,
    HIP.TotalWeightedTagInfluence,
    HIP.NumTagsOnPost,
    HIP.PostEngagementIndex,
    HIP.RankWithinPostType,
    HIP.AvgOwnerPostEngagement,
    HIP.TotalEditHistoryEntries,
    HIP.UniqueEditors,
    HIP.HasRapidSelfEdit,
    HIP.IsAcceptedAnswerByDifferentUser,
    -- Complicated calculation with NULLIF for division by zero and COALESCE for default value
    COALESCE(
        NULLIF(HIP.Score, 0) / NULLIF(HIP.ParentQuestionScore, 0),
        0.0
    ) AS AnswerScoreToQuestionScoreRatio,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = HIP.PostId AND V.VoteTypeId = 5) AS TotalFavoritesLegacy
FROM HighImpactPosts AS HIP
WHERE HIP.PostTypeName = 'Answer'
AND HIP.Score > 50 -- Predicate: High scoring answers
AND HIP.OwnerReputation > 10000 -- Predicate: By very reputable users
AND HIP.DaysSinceLastAccess < 180 -- Predicate: Very active owners (accessed in last 6 months)
AND HIP.ParentQuestionScore IS NOT NULL -- Predicate: Ensure parent question score exists
AND HIP.ParentQuestionViewCount IS NOT NULL -- Predicate: Ensure parent question view count exists
AND HIP.PostAgeDays < 730 -- Predicate: Relatively recent answers (within 2 years)
AND HIP.TotalEditHistoryEntries > 0 -- Predicate: Answers that have been edited
-- Complicated predicate: Exclude underperforming answers from otherwise good users
AND NOT (HIP.PostEngagementIndex < HIP.AvgOwnerPostEngagement * 0.5 AND HIP.Score < 100)

ORDER BY PostEngagementIndex DESC, AnalysisCategory, PostId
LIMIT 200;
