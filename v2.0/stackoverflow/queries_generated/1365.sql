-- {"query": "1365.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3562} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user engagement and basic activity metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS ProfileViews,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsAuthored,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreReceived,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreReceived,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(u.LastAccessDate) AS LastActivityDate,
        -- Calculate average non-empty comment length for the user, handling NULLs
        AVG(CASE WHEN LENGTH(TRIM(c.Text)) > 0 THEN LENGTH(TRIM(c.Text)) ELSE NULL END) AS AvgCommentLength,
        -- Correlated subquery: Check if user has ever posted a question mentioning 'performance' in tags or title
        EXISTS (
            SELECT 1
            FROM Posts sqp
            WHERE sqp.OwnerUserId = u.Id
              AND sqp.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
              AND (LOWER(sqp.Tags) LIKE '%<performance>%' OR LOWER(sqp.Title) LIKE '%performance%')
        ) AS HasPerformanceRelatedQuestion,
        -- Non-correlated subquery in a CASE statement: Compare user's reputation to global average for users created in the same year
        CASE WHEN u.Reputation > COALESCE((
            SELECT AVG(u2.Reputation)
            FROM Users u2
            WHERE EXTRACT(YEAR FROM u2.CreationDate) = EXTRACT(YEAR FROM u.CreationDate)
        ), 0) THEN TRUE ELSE FALSE END AS AboveAvgReputationForCohort
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostQualityHistoryExtended AS (
    -- CTE 2: Evaluate post quality, view trends, and historical changes using window functions and complex logic
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(p.CommentCount, 0) AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.LastEditDate,
        ph_closed.Comment AS CloseReasonComment, -- Contains CloseReasonId if PostHistoryTypeId = 10
        -- Custom Post Quality Index (weighted sum, emphasizing answers and favorites)
        (
            COALESCE(p.Score, 0) * 0.35 +
            COALESCE(p.ViewCount, 0) * 0.05 +
            COALESCE(NULLIF(p.AnswerCount, 0), 0) * 0.25 + -- NULLIF to avoid division by zero implicitly
            COALESCE(p.FavoriteCount, 0) * 0.25 +
            COALESCE(p.CommentCount, 0) * 0.10
        ) AS PostQualityIndex,
        -- Count specific post history types (edits, closures, reopenings) using correlated subqueries
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Edit %')) AS TotalEditRevisions,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')) AS TotalCloseEvents,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened')) AS TotalReopenEvents,
        -- Window function: Running average score for the user's posts over time
        AVG(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RunningAvgUserPostScore,
        -- Window function: Score change from the previous post by the same user
        COALESCE(p.Score, 0) - LAG(COALESCE(p.Score, 0), 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS ScoreDeltaFromPreviousPost,
        -- Determine if an answer post was accepted
        CASE
            WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') AND
                 p.Id = (SELECT pa.AcceptedAnswerId FROM Posts pa WHERE pa.Id = p.ParentId)
            THEN 'Accepted Answer'
            WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
            THENCE 'Unaccepted Answer'
            ELSE 'N/A'
        END AS AnswerStatus,
        -- Window function: Rank posts by quality within each post type, ordered by creation date
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC, p.Score DESC) AS PostTypeCreationRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph_closed ON p.Id = ph_closed.PostId AND ph_closed.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    WHERE p.OwnerUserId IS NOT NULL -- Exclude community owned posts without a clear user
      AND p.PostTypeId IN ((SELECT Id FROM PostTypes WHERE Name = 'Question'), (SELECT Id FROM PostTypes WHERE Name = 'Answer')) -- Focus on Q&A
),
AggregatedUserPostStats AS (
    -- CTE 3: Aggregate detailed post stats by user from PostQualityHistoryExtended
    SELECT
        pqhe.OwnerUserId AS UserId,
        COUNT(pqhe.PostId) AS UserTotalPosts,
        SUM(pqhe.PostQualityIndex) AS UserTotalQualityIndex,
        AVG(pqhe.PostQualityIndex) AS UserAvgPostQualityIndex,
        SUM(pqhe.TotalEditRevisions) AS TotalEditsMadeOnUserPosts,
        SUM(pqhe.TotalCloseEvents) AS TotalCloseEventsOnUserPosts,
        SUM(pqhe.TotalReopenEvents) AS TotalReopenEventsOnUserPosts,
        -- Average Post Quality Index for Questions vs. Answers
        AVG(CASE WHEN pqhe.PostTypeName = 'Question' THEN pqhe.PostQualityIndex ELSE NULL END) AS AvgQuestionQualityIndex,
        AVG(CASE WHEN pqhe.PostTypeName = 'Answer' THEN pqhe.PostQualityIndex ELSE NULL END) AS AvgAnswerQualityIndex,
        -- Max Score and ViewCount for a single post by this user
        MAX(pqhe.PostScore) AS MaxSinglePostScore,
        MAX(pqhe.PostViewCount) AS MaxSinglePostViewCount,
        -- Identify users with at least one 'duplicate' or 'linked' post
        EXISTS (
            SELECT 1 FROM PostLinks pl
            WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = pqhe.OwnerUserId)
            AND pl.LinkTypeId IN ((SELECT Id FROM LinkTypes WHERE Name = 'Duplicate'), (SELECT Id FROM LinkTypes WHERE Name = 'Linked'))
        ) AS HasAssociatedLinks,
        -- Identify users whose posts have ever been closed due to 'Off-topic' (using PostHistory's Comment field for CloseReasonId)
        EXISTS (
            SELECT 1 FROM PostHistory ph_reason
            WHERE ph_reason.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = pqhe.OwnerUserId)
            AND ph_reason.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
            AND ph_reason.Comment = (SELECT CAST(Id AS VARCHAR) FROM CloseReasonTypes WHERE Name = 'Off-topic') -- Assuming Comment stores Id as string
        ) AS HasOffTopicClosure
    FROM PostQualityHistoryExtended pqhe
    GROUP BY pqhe.OwnerUserId
),
ProblematicTagAnalysis AS (
    -- CTE 4: Analyze problematic tags (low score, high closure rate) using set operators and string functions
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        EXTRACT(YEAR FROM p.CreationDate) AS TagYear,
        COUNT(p.Id) AS PostsWithTag,
        AVG(COALESCE(p.Score, 0)) AS AvgScoreForTag,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewsForTag,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsWithTag,
        -- Calculate percentage of closed posts for the tag
        COALESCE(CAST(SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(p.Id), 0), 0) AS ClosureRateForTag
    FROM Posts p
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') -- Only questions have tags
      AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 -- Ensure valid tags
    GROUP BY 1, 2
    HAVING COUNT(p.Id) >= 50 -- Minimum posts for statistical significance
),
TopProblematicTags AS (
    -- CTE 5: Filter problematic tags based on thresholds and combine with UNION ALL
    SELECT
        pta.TagName,
        pta.TagYear,
        pta.PostsWithTag,
        pta.AvgScoreForTag,
        pta.AvgViewsForTag,
        pta.ClosureRateForTag,
        'LowScoreHighClosure' AS ProblemType,
        RANK() OVER (PARTITION BY pta.TagYear ORDER BY pta.AvgScoreForTag ASC, pta.ClosureRateForTag DESC) AS RankWithinYear
    FROM ProblematicTagAnalysis pta
    WHERE pta.AvgScoreForTag < 10 AND pta.ClosureRateForTag > 0.30 -- Low score AND high closure
    UNION ALL
    SELECT
        pta.TagName,
        pta.TagYear,
        pta.PostsWithTag,
        pta.AvgScoreForTag,
        pta.AvgViewsForTag,
        pta.ClosureRateForTag,
        'HighViewLowEngagement' AS ProblemType,
        RANK() OVER (PARTITION BY pta.TagYear ORDER BY pta.AvgViewsForTag DESC, pta.AvgScoreForTag ASC) AS RankWithinYear
    FROM ProblematicTagAnalysis pta
    WHERE pta.AvgViewsForTag > 5000 AND pta.AvgScoreForTag < 5 -- High views BUT low score (engagement)
)
-- Final SELECT statement: Combine all user and tag analysis, apply final filtering and ordering
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.LastActivityDate,
    ue.ProfileViews,
    ue.TotalPostsAuthored,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.TotalCommentsMade,
    ue.TotalBadgesEarned,
    COALESCE(ue.AvgCommentLength, 0.0) AS UserAvgCommentLength,
    ue.HasPerformanceRelatedQuestion,
    ue.AboveAvgReputationForCohort,
    aups.UserTotalQualityIndex,
    aups.UserAvgPostQualityIndex,
    aups.AvgQuestionQualityIndex,
    aups.AvgAnswerQualityIndex,
    aups.MaxSinglePostScore,
    aups.MaxSinglePostViewCount,
    aups.TotalEditsMadeOnUserPosts,
    aups.TotalCloseEventsOnUserPosts,
    aups.TotalReopenEventsOnUserPosts,
    aups.HasAssociatedLinks,
    aups.HasOffTopicClosure,
    -- Window function: Overall rank for users based on a combination of reputation and post quality
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC, aups.UserTotalQualityIndex DESC) AS UserOverallRank,
    -- Window function: NTILE to categorize users into 10 deciles based on answer quality
    NTILE(10) OVER (ORDER BY COALESCE(aups.AvgAnswerQualityIndex, 0) DESC) AS AnswerQualityDecile,
    -- String expression: Create a user summary string
    CONCAT(
        ue.DisplayName,
        ' (Rep: ', CAST(ue.Reputation AS VARCHAR), ') - ',
        CASE
            WHEN ue.AboveAvgReputationForCohort AND aups.UserAvgPostQualityIndex > 100 THEN 'High-Impact Contributor'
            WHEN aups.TotalCloseEventsOnUserPosts > aups.TotalReopenEventsOnUserPosts AND aups.HasOffTopicClosure THEN 'Content-Challenged User'
            WHEN ue.QuestionCount > ue.AnswerCount AND ue.TotalPostsAuthored > 20 THEN 'Question-Focused Expert'
            ELSE 'General Participant'
        END,
        ' (Posts: ', CAST(ue.TotalPostsAuthored AS VARCHAR), ', Badges: ', CAST(ue.TotalBadgesEarned AS VARCHAR), ')'
    ) AS UserSummaryDescription,
    tpt.ProblemType AS TopProblematicTagType,
    tpt.TagName AS TopProblematicTagName,
    tpt.TagYear AS TopProblematicTagYear,
    tpt.ClosureRateForTag AS TopProblematicTagClosureRate
FROM UserEngagement ue
LEFT JOIN AggregatedUserPostStats aups ON ue.UserId = aups.UserId
LEFT JOIN TopProblematicTags tpt ON ue.HasPerformanceRelatedQuestion = TRUE AND tpt.TagName = 'performance' AND tpt.RankWithinYear = 1 -- Joining specific tag info for relevant users
WHERE ue.Reputation >= 5000 -- Filter for significant users
  AND COALESCE(aups.UserTotalQualityIndex, 0) > 0 -- Ensure user has some quality metric
  AND (aups.AvgQuestionQualityIndex > (SELECT AVG(AvgQuestionQualityIndex) FROM AggregatedUserPostStats) OR aups.AvgAnswerQualityIndex > (SELECT AVG(AvgAnswerQualityIndex) FROM AggregatedUserPostStats)) -- Only users whose questions OR answers are above average
ORDER BY UserOverallRank ASC, ue.LastActivityDate DESC
LIMIT 500;
