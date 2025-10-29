-- {"query": "1894.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4069} 

WITH UserEngagement AS (
    -- Summarize user engagement metrics and join with Badges and Comments
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalPostFavorites,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersReceived,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COALESCE(u.Location, 'Unknown') AS UserLocation
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
PostDetails AS (
    -- Extract detailed post metrics, including string manipulations and window functions
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.ClosedDate,
        p.AcceptedAnswerId,
        p.ParentId,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        -- Extract first 50 chars of body if title is null or default title
        COALESCE(p.Title, SUBSTRING(p.Body, 1, 50) || '...') AS DisplayTitle,
        -- Check if post body contains specific keywords (case-insensitive)
        CASE WHEN LOWER(p.Body) LIKE '%performance%' OR LOWER(p.Body) LIKE '%optimization%' THEN 1 ELSE 0 END AS ContainsPerformanceKeyword,
        -- Window function: Rank posts by score within each post type
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRank,
        -- Window function: Calculate average score of posts by the same owner in a rolling 7-day window
        AVG(p.Score) OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate
            ROWS BETWEEN INTERVAL '7 DAY' PRECEDING AND CURRENT ROW
        ) AS AvgOwnerScoreLast7Days,
        -- Window function: Get the score of the previous post by the same owner, default to 0 if none
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        -- PostgreSQL specific: Aggregate tags into a comma-separated string
        COALESCE((SELECT STRING_AGG(unnest_tag.tag_name, ',') FROM unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as unnest_tag(tag_name)), 'N/A') AS TagList,
        -- Count of unique tags for the post, defaulting to 0 if no tags
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1), 0) AS TagCount,
        -- Correlated subquery: Check if this post has more up/accepted/favorite votes than the average for posts by the same user on the same day
        (SELECT COUNT(v_corr.Id)
         FROM Votes AS v_corr
         WHERE v_corr.PostId = p.Id AND v_corr.VoteTypeId IN (1,2,5)
        ) > (
            SELECT COALESCE(AVG(v_avg.vote_count), 0)
            FROM (
                SELECT p_avg.Id, COUNT(v_avg_inner.Id) AS vote_count
                FROM Posts AS p_avg
                LEFT JOIN Votes AS v_avg_inner ON p_avg.Id = v_avg_inner.PostId AND v_avg_inner.VoteTypeId IN (1,2,5)
                WHERE p_avg.OwnerUserId = p.OwnerUserId
                  AND DATE_TRUNC('day', p_avg.CreationDate) = DATE_TRUNC('day', p.CreationDate)
                GROUP BY p_avg.Id
            ) AS v_avg
        ) AS HasAboveAvgDailyVotesForUser,
        p.Tags AS RawTags -- Keep raw tags for primary tag extraction later in correlated subqueries
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1 -- Exclude community user (-1) and deleted users
),
PostHistoryAnalysis AS (
    -- Analyze post history for edits, closures, and involved users
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditDateByHistory,
        MIN(ph.CreationDate) AS InitialCreationDateByHistory,
        -- Calculate time to first edit in hours, NULL if no edits
        EXTRACT(EPOCH FROM (MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) - MIN(ph.CreationDate))) / 3600 AS TimeToFirstEditHours,
        -- Aggregate unique display names of users who edited the post
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, ph.UserDisplayName, 'Unknown Editor'), ', ') AS EditorsList
    FROM PostHistory AS ph
    LEFT JOIN Users AS u ON ph.UserId = u.Id
    GROUP BY ph.PostId
),
LinkedPostAnalysis AS (
    -- Identify posts that are linked to or duplicates of other posts
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS LinkedToCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicateOfCount,
        -- List of related post IDs
        STRING_AGG(DISTINCT pl.RelatedPostId::varchar, ',') AS RelatedPostsList,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks AS pl
    GROUP BY pl.PostId
),
VoteAnalysis AS (
    -- Summarize vote counts and bounty amounts for each post
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes,
        SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes AS v
    GROUP BY v.PostId
),
TagMetrics AS (
    -- Explode tags from Posts table to individual rows for aggregation
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
TagAggregates AS (
    -- Calculate aggregate metrics for each tag, including average scores and view counts
    SELECT
        tm.TagName,
        COUNT(DISTINCT tm.PostId) AS PostsWithTag,
        COALESCE(AVG(pd.Score), 0) AS AvgScoreForTag,
        COALESCE(AVG(pd.ViewCount), 0) AS AvgViewCountForTag,
        COALESCE(SUM(pd.CommentCount), 0) AS TotalCommentsForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT tm.PostId) DESC) AS TagPopularityRank
    FROM TagMetrics AS tm
    JOIN PostDetails AS pd ON tm.PostId = pd.PostId
    GROUP BY tm.TagName
),
CombinedAnalysis AS (
    -- First analysis segment: High-impact posts by high-reputation users, focusing on "performance" keywords
    SELECT
        'HighRepUserPostActivity' AS AnalysisSegment,
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.GoldBadges,
        pd.PostId,
        pd.PostTypeName,
        pd.DisplayTitle,
        pd.PostCreationDate,
        pd.Score AS PostScore,
        pd.ViewCount AS PostViewCount,
        pd.CommentCount AS PostCommentCount,
        COALESCE(va.Upvotes, 0) AS PostUpvotes,
        COALESCE(va.Downvotes, 0) AS PostDownvotes,
        COALESCE(ph.EditCount, 0) AS PostEditCount,
        COALESCE(lpa.LinkedToCount, 0) AS PostLinkedToCount,
        COALESCE(lpa.DuplicateOfCount, 0) AS PostDuplicateOfCount,
        ph.EditorsList,
        pd.BodyLength,
        pd.ContainsPerformanceKeyword,
        pd.PostScoreRank,
        pd.AvgOwnerScoreLast7Days,
        pd.HasAboveAvgDailyVotesForUser,
        pd.TagList,
        pd.TagCount,
        -- Correlated subquery to get average score of the primary tag
        (SELECT ta_prim.AvgScoreForTag FROM TagAggregates ta_prim WHERE ta_prim.TagName = (SELECT (string_to_array(SUBSTRING(pd.RawTags, 2, LENGTH(pd.RawTags)-2), '><'))[1] FROM Posts WHERE Id = pd.PostId AND pd.RawTags IS NOT NULL AND LENGTH(pd.RawTags) > 2 LIMIT 1)) AS PrimaryTagAvgScore,
        -- Days taken to close a post, NULL if not closed or initial history missing
        CASE
            WHEN pd.ClosedDate IS NOT NULL AND ph.InitialCreationDateByHistory IS NOT NULL THEN
                EXTRACT(EPOCH FROM (pd.ClosedDate - ph.InitialCreationDateByHistory)) / (24 * 3600)
            ELSE NULL
        END AS DaysToClose,
        -- Complicated calculation: Ratio of Upvotes to (Downvotes + AcceptedAnswerVotes + 1 to avoid div by zero)
        CASE WHEN COALESCE(va.Downvotes, 0) + COALESCE(va.AcceptedAnswerVotes, 0) = 0 THEN 1000.0 -- Assign a high value for very positive posts
             ELSE (COALESCE(va.Upvotes, 0) * 1.0) / (COALESCE(va.Downvotes, 0) + COALESCE(va.AcceptedAnswerVotes, 0))
        END AS UpvoteToNegativeRatio,
        -- Average bounty amount for posts that had bounties
        (SELECT COALESCE(AVG(v.BountyAmount), 0) FROM Votes v WHERE v.PostId = pd.PostId AND v.VoteTypeId = 8) AS AvgBountyOnPost
    FROM UserEngagement AS ue
    JOIN PostDetails AS pd ON ue.UserId = pd.OwnerUserId
    LEFT JOIN PostHistoryAnalysis AS ph ON pd.PostId = ph.PostId
    LEFT JOIN LinkedPostAnalysis AS lpa ON pd.PostId = lpa.PostId
    LEFT JOIN VoteAnalysis AS va ON pd.PostId = va.PostId
    WHERE ue.Reputation > 5000 -- Filter for users with high reputation
      AND pd.ViewCount > 500 -- Filter for popular posts
      AND pd.PostCreationDate >= '2021-01-01' -- Limit date range
      AND pd.ContainsPerformanceKeyword = 1 -- Only posts mentioning performance/optimization
    
    UNION ALL
    
    -- Second analysis segment: Recently edited posts by very active users with detailed AboutMe, showing different filtering logic
    SELECT
        'RecentEditedPostAnalysis' AS AnalysisSegment,
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.GoldBadges,
        pd.PostId,
        pd.PostTypeName,
        pd.DisplayTitle,
        pd.PostCreationDate,
        pd.Score AS PostScore,
        pd.ViewCount AS PostViewCount,
        pd.CommentCount AS PostCommentCount,
        COALESCE(va.Upvotes, 0) AS PostUpvotes,
        COALESCE(va.Downvotes, 0) AS PostDownvotes,
        COALESCE(ph.EditCount, 0) AS PostEditCount,
        COALESCE(lpa.LinkedToCount, 0) AS PostLinkedToCount,
        COALESCE(lpa.DuplicateOfCount, 0) AS PostDuplicateOfCount,
        ph.EditorsList,
        pd.BodyLength,
        pd.ContainsPerformanceKeyword,
        pd.PostScoreRank,
        pd.AvgOwnerScoreLast7Days,
        pd.HasAboveAvgDailyVotesForUser,
        pd.TagList,
        pd.TagCount,
        (SELECT ta_prim.AvgScoreForTag FROM TagAggregates ta_prim WHERE ta_prim.TagName = (SELECT (string_to_array(SUBSTRING(pd.RawTags, 2, LENGTH(pd.RawTags)-2), '><'))[1] FROM Posts WHERE Id = pd.PostId AND pd.RawTags IS NOT NULL AND LENGTH(pd.RawTags) > 2 LIMIT 1)) AS PrimaryTagAvgScore,
        CASE
            WHEN pd.ClosedDate IS NOT NULL AND ph.InitialCreationDateByHistory IS NOT NULL THEN
                EXTRACT(EPOCH FROM (pd.ClosedDate - ph.InitialCreationDateByHistory)) / (24 * 3600)
            ELSE NULL
        END AS DaysToClose,
        CASE WHEN COALESCE(va.Downvotes, 0) + COALESCE(va.AcceptedAnswerVotes, 0) = 0 THEN 1000.0
             ELSE (COALESCE(va.Upvotes, 0) * 1.0) / (COALESCE(va.Downvotes, 0) + COALESCE(va.AcceptedAnswerVotes, 0))
        END AS UpvoteToNegativeRatio,
        (SELECT COALESCE(AVG(v.BountyAmount), 0) FROM Votes v WHERE v.PostId = pd.PostId AND v.VoteTypeId = 8) AS AvgBountyOnPost
    FROM UserEngagement AS ue
    JOIN PostDetails AS pd ON ue.UserId = pd.OwnerUserId
    LEFT JOIN PostHistoryAnalysis AS ph ON pd.PostId = ph.PostId
    LEFT JOIN LinkedPostAnalysis AS lpa ON pd.PostId = lpa.PostId
    LEFT JOIN VoteAnalysis AS va ON pd.PostId = va.PostId
    JOIN Users u_main ON ue.UserId = u_main.Id -- Join Users again to access AboutMe
    WHERE ph.LastEditDateByHistory >= NOW() - INTERVAL '60 days' -- Posts edited in the last two months
      AND ue.TotalPosts > 50 -- Very active poster
      AND pd.Score > 20 -- Only consider reasonably scored posts
      AND u_main.AboutMe IS NOT NULL AND LENGTH(u_main.AboutMe) > 100 -- Users who care to write a detailed AboutMe
)
-- Final selection from combined analysis, ordered and limited
SELECT
    *
FROM CombinedAnalysis
ORDER BY AnalysisSegment, Reputation DESC, PostScore DESC
LIMIT 2000;
