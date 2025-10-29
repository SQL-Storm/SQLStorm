-- {"query": "1617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2775} 

WITH UserActivityCTE AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.WebsiteUrl,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountOnPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.CreationDate) AS LastPostActivity,
        MIN(p.CreationDate) AS FirstPostActivity,
        SUM(p.Score) AS TotalPostScore,
        -- Correlated subquery for average score of answers that were accepted by original questioners
        (
            SELECT AVG(pa.Score)
            FROM Posts pa
            WHERE pa.OwnerUserId = u.Id
              AND pa.PostTypeId = 2
              AND pa.Id IN (SELECT pq.AcceptedAnswerId FROM Posts pq WHERE pq.PostTypeId = 1 AND pq.AcceptedAnswerId IS NOT NULL)
        ) AS AvgAcceptedAnswerScore,
        -- Correlated subquery for count of up-votes received on the user's own posts
        (
            SELECT COUNT(vp.Id)
            FROM Posts up
            JOIN Votes vp ON up.Id = vp.PostId
            WHERE up.OwnerUserId = u.Id AND vp.VoteTypeId = 2
        ) AS UpVotesReceivedOnOwnPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.WebsiteUrl, u.Location
),
PostTaggingAndEditingCTE AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        LOWER(TRIM(t_unnest.Tag)) AS Tag, -- Unnested tag, trimmed and lowercased
        -- Count of self-edits for this specific post (body or tags)
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 6, 4) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS SelfEditCount,
        -- Ranking of posts by score for each owner (window function)
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRankByOwner,
        -- Cumulative average score of all posts from this user up to this post's creation date (window function)
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS CumulativeAvgPostScoreByOwner,
        -- Lagged score of the previous post by the same owner (window function)
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag) t_unnest ON p.Tags IS NOT NULL
    WHERE p.OwnerUserId IS NOT NULL -- Only posts with an owner
      AND p.PostTypeId IN (1, 2) -- Only questions and answers
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, t_unnest.Tag
),
TagInfluenceCTE AS (
    SELECT
        pte.Tag,
        COUNT(DISTINCT pte.PostId) AS TaggedPostCount,
        SUM(pte.PostScore) AS TotalTagScore,
        AVG(pte.PostViewCount) AS AvgTagViewCount,
        MAX(t.Count) AS GlobalTagCount, -- Max global count from Tags table
        MAX(CASE WHEN t.IsModeratorOnly THEN 1 ELSE 0 END) AS IsModeratorOnlyTag,
        -- Calculate percentage of posts with positive score for this tag, handling division by zero
        CAST(SUM(CASE WHEN pte.PostScore > 0 THEN 1 ELSE 0 END) AS NUMERIC) * 100 / NULLIF(COUNT(pte.PostId), 0) AS PositiveScorePercentage
    FROM PostTaggingAndEditingCTE pte
    LEFT JOIN Tags t ON LOWER(t.TagName) = pte.Tag
    GROUP BY pte.Tag
    HAVING COUNT(DISTINCT pte.PostId) > 50 -- Only consider tags with significant activity
),
DailyEngagementCTE AS (
    SELECT
        CAST(CreationDate AS DATE) AS ActivityDate,
        COUNT(DISTINCT Id) AS TotalDailyPosts,
        COUNT(DISTINCT OwnerUserId) AS TotalDailyActiveUsers,
        SUM(Score) AS TotalDailyScore,
        -- Seven-day moving average of daily post score (window function)
        AVG(SUM(Score)) OVER (ORDER BY CAST(CreationDate AS DATE) ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS SevenDayMovingAvgScore
    FROM Posts
    WHERE CreationDate IS NOT NULL AND OwnerUserId IS NOT NULL
    GROUP BY CAST(CreationDate AS DATE)
),
DiverseUsersCTE AS (
    -- Set operator (UNION) to identify two distinct groups of highly engaged users
    -- Group 1: Users with very high reputation and good average score on accepted answers
    SELECT UserId FROM UserActivityCTE WHERE Reputation > 50000 AND AvgAcceptedAnswerScore IS NOT NULL AND AvgAcceptedAnswerScore > 15
    UNION
    -- Group 2: Users with a large number of badges and substantial posting activity
    SELECT UserId FROM UserActivityCTE WHERE TotalBadges >= 50 AND TotalPosts >= 200
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.UserProfileViews,
    u.TotalPosts,
    u.TotalQuestions,
    u.TotalAnswers,
    u.TotalComments,
    u.TotalFavoriteCountOnPosts,
    u.TotalBadges,
    u.LastPostActivity,
    u.AvgAcceptedAnswerScore,
    u.UpVotesReceivedOnOwnPosts,
    COALESCE(AVG(pte.PostScore), 0) AS AvgScoreOfTaggedPosts,
    COALESCE(MAX(pte.SelfEditCount), 0) AS MaxSelfEditsOnAnyPost,
    COALESCE(SUM(CASE WHEN pte.PostScoreRankByOwner = 1 THEN 1 ELSE 0 END), 0) AS TopRankedPostsCount,
    COALESCE(SUM(pte.PrevPostScore), 0) AS SumOfPreviousPostScores,
    COUNT(DISTINCT pte.Tag) AS DistinctTagsContributed,
    STRING_AGG(DISTINCT pte.Tag, ', ' ORDER BY pte.Tag) AS AllTagsContributed,
    MAX(tie.TaggedPostCount) AS MaxTaggedPostCountForAnyTag,
    AVG(tie.PositiveScorePercentage) AS AvgTagPositiveScorePercentage,
    de.ActivityDate AS LastActivityDateForDailyMetrics,
    de.TotalDailyPosts AS PostsOnLastActivityDate,
    de.TotalDailyActiveUsers AS ActiveUsersOnLastActivityDate,
    de.SevenDayMovingAvgScore AS SevenDayAvgScoreAroundLastActivity,
    -- Complicated predicate/expression for user influence categorization
    CASE
        WHEN u.Reputation > 10000 AND u.UpVotesReceivedOnOwnPosts > 5000 AND u.TotalPosts > 100 AND u.AvgAcceptedAnswerScore IS NOT NULL AND u.AvgAcceptedAnswerScore > 10 THEN 'Elite Contributor'
        WHEN u.Reputation > 5000 AND u.TotalQuestions > 10 AND u.TotalAnswers > 50 AND COALESCE(AVG(pte.PostScore), 0) > 5 THEN 'Prolific Supporter'
        WHEN u.TotalBadges >= 10 AND u.TotalComments >= 50 AND du.UserId IS NOT NULL THEN 'Community Engager (Diverse)' -- User falls into one of the UNIONed groups
        ELSE 'Active User'
    END AS UserInfluenceCategory,
    -- NULL logic for Location and shortened WebsiteUrl using string expressions
    COALESCE(NULLIF(TRIM(u.Location), ''), 'Unknown Location') AS UserLocationDetail,
    SUBSTRING(COALESCE(u.WebsiteUrl, ''), 1, 50) AS ShortenedWebsiteUrl,
    -- Correlated subquery for counting duplicate links originating from user's posts
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId IN (SELECT p_link.Id FROM Posts p_link WHERE p_link.OwnerUserId = u.UserId)
          AND pl.LinkTypeId = 3 -- Duplicate link type
    ) AS DuplicateLinkCountForOwnPosts
FROM UserActivityCTE u
LEFT JOIN PostTaggingAndEditingCTE pte ON u.UserId = pte.OwnerUserId
LEFT JOIN TagInfluenceCTE tie ON pte.Tag = tie.Tag
LEFT JOIN DailyEngagementCTE de ON CAST(u.LastPostActivity AS DATE) = de.ActivityDate
LEFT JOIN DiverseUsersCTE du ON u.UserId = du.UserId
WHERE u.Reputation > 100 -- Minimum reputation for consideration
  AND u.TotalPosts > 5 -- Minimum posts
  AND u.TotalQuestions + u.TotalAnswers > 0 -- Must have at least one question or answer
  AND u.LastPostActivity IS NOT NULL -- Must have some post activity
  -- Complicated predicate combining multiple conditions for filtering users
  AND (u.UserProfileViews > 500 OR u.TotalFavoriteCountOnPosts > 10)
  AND (pte.PostId IS NULL OR pte.SelfEditCount < 5 OR pte.PostScore > 50) -- Either no posts or specific conditions on edited posts
  -- NOT EXISTS subquery: User has no negatively scored closed questions
  AND NOT EXISTS (
    SELECT 1 FROM Posts closed_p
    WHERE closed_p.OwnerUserId = u.UserId
      AND closed_p.ClosedDate IS NOT NULL
      AND closed_p.PostTypeId = 1
      AND closed_p.Score < 0
  )
GROUP BY
    u.UserId, u.DisplayName, u.Reputation, u.UserProfileViews, u.TotalPosts, u.TotalQuestions, u.TotalAnswers,
    u.TotalComments, u.TotalFavoriteCountOnPosts, u.TotalBadges, u.LastPostActivity, u.AvgAcceptedAnswerScore,
    u.UpVotesReceivedOnOwnPosts, de.ActivityDate, de.TotalDailyPosts, de.TotalDailyActiveUsers, de.SevenDayMovingAvgScore,
    u.Location, u.WebsiteUrl, du.UserId
HAVING
    COUNT(DISTINCT pte.PostId) > 0 -- Ensure we only consider users who have posts relevant to PostTaggingAndEditingCTE
    AND COALESCE(MAX(pte.SelfEditCount), 0) >= 1 -- At least one self-edit across their posts
    AND u.Reputation > 200 -- Aggregate filter (or just filter on u.Reputation directly)
ORDER BY
    u.Reputation DESC, COALESCE(AVG(pte.PostScore), 0) DESC, u.UpVotesReceivedOnOwnPosts DESC
LIMIT 100;
