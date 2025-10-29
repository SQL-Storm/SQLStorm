-- {"query": "1643.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2967} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsCreated,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersCreated,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived, -- Using COALESCE for sums that might be NULL
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        -- Calculate the average score of posts by this user
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        -- Find the maximum bounty amount received by any post owned by this user
        (SELECT COALESCE(MAX(v.BountyAmount), 0) FROM Votes AS v WHERE v.PostId IN (SELECT p_inner.Id FROM Posts AS p_inner WHERE p_inner.OwnerUserId = u.Id) AND v.VoteTypeId = 9) AS MaxBountyReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate -- Example of FILTER clause for specific badge
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' -- Filter for users created after a certain date
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        COALESCE(p.Title, LEFT(p.Body, 100)) AS PostTitleOrExcerpt, -- Use COALESCE for title or body excerpt
        LENGTH(p.Body) AS BodyLength,
        -- Extract tags into an array and count them, handling NULLs gracefully
        CARDINALITY(string_to_array(SUBSTRING(COALESCE(p.Tags, '><') FROM 2 FOR LENGTH(COALESCE(p.Tags, '><'))-2), '><')) AS TagCount,
        -- Calculate the "freshness score" based on recent activity in hours
        EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)) / 3600 AS HoursSinceLastActivity,
        -- Correlated subquery: Get the score of the accepted answer if available
        (SELECT pa.Score FROM Posts AS pa WHERE pa.Id = p.AcceptedAnswerId AND pa.PostTypeId = 2) AS AcceptedAnswerScore,
        -- Determine if the post body is "long"
        CASE WHEN LENGTH(p.Body) > 1000 THEN 'Long' WHEN LENGTH(p.Body) > 300 THEN 'Medium' ELSE 'Short' END AS BodyLengthCategory
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
      AND p.Score > 0 -- Only posts with positive score
      AND p.ViewCount IS NOT NULL AND p.ViewCount > 0 -- Exclude posts without view count or zero views
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryTypes,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenedEvents,
        -- Correlated subquery: Find the earliest edit date for a post
        (SELECT MIN(ph_inner.CreationDate) FROM PostHistory AS ph_inner WHERE ph_inner.PostId = ph.PostId AND ph_inner.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        -- Extract the CloseReasonType for the latest closure if any
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN LEFT(ph.Comment, 20) ELSE NULL END) AS LatestCloseReasonExcerpt
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        -- Calculate MaxLinkedPostAgeDiff by joining Posts within the CTE
        MAX(CASE WHEN pl.LinkTypeId = 1 THEN EXTRACT(EPOCH FROM (p_related.CreationDate - p_main.CreationDate)) / (3600*24) ELSE NULL END) AS MaxLinkedPostAgeDiffDays
    FROM PostLinks AS pl
    JOIN Posts AS p_main ON pl.PostId = p_main.Id
    JOIN Posts AS p_related ON pl.RelatedPostId = p_related.Id
    GROUP BY pl.PostId
),
TopTagsPerPost AS (
    SELECT
        p.Id AS PostId,
        UNNEST(string_to_array(SUBSTRING(COALESCE(p.Tags, '><') FROM 2 FOR LENGTH(COALESCE(p.Tags, '><'))-2), '><')) AS TagName
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 AND LENGTH(p.Tags) > 2 -- Ensure tags exist and are not empty
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalPostsCreated,
    pca.PostId,
    pca.PostTitleOrExcerpt,
    pca.Score AS PostScore,
    pca.ViewCount AS PostViewCount,
    pca.AnswerCount,
    pca.CommentCount,
    pca.FavoriteCount,
    pca.BodyLength,
    pca.TagCount,
    pca.HoursSinceLastActivity,
    pca.AcceptedAnswerScore,
    pca.BodyLengthCategory,
    phd.TotalHistoryEntries,
    phd.DistinctHistoryTypes,
    phd.TotalEditEvents,
    phd.TotalClosedEvents,
    phd.TotalReopenedEvents,
    phd.FirstEditDate,
    phd.LatestCloseReasonExcerpt,
    COALESCE(pla.LinkedPostsCount, 0) AS LinkedPostsCount,
    COALESCE(pla.DuplicatePostsCount, 0) AS DuplicatePostsCount,
    pla.MaxLinkedPostAgeDiffDays,
    -- Window function: Rank users by reputation within their creation year
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM ues.UserCreationDate) ORDER BY ues.Reputation DESC) AS RankInCreationYear,
    -- Window function: Average score of posts for this user, partitioned by post type
    AVG(pca.Score) OVER (PARTITION BY pca.OwnerUserId, pca.PostTypeId) AS AvgScoreForUserPostType,
    -- String manipulation: Check if post title contains common keywords (case-insensitive)
    CASE
        WHEN LOWER(pca.PostTitleOrExcerpt) LIKE '%sql%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%database%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%query%' THEN 'DB_Related_Post'
        WHEN LOWER(pca.PostTitleOrExcerpt) LIKE '%python%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%java%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%javascript%' THEN 'Programming_Language_Post'
        WHEN LOWER(pca.PostTitleOrExcerpt) LIKE '%web%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%html%' OR LOWER(pca.PostTitleOrExcerpt) LIKE '%css%' THEN 'Web_Dev_Post'
        ELSE 'Other_Category_Post'
    END AS PostCategoryByTitle,
    -- Complicated calculation: "Engagement Index" combining various metrics, handling NULLs
    (COALESCE(pca.Score, 0) * 0.5 + COALESCE(pca.FavoriteCount, 0) * 1.5 + COALESCE(pca.CommentCount, 0) * 0.8 + COALESCE(pca.AcceptedAnswerScore, 0) * 2 - (COALESCE(pca.HoursSinceLastActivity, 0) / 100)) AS EngagementIndex,
    -- NULL logic and CASE for Post Status
    CASE
        WHEN pca.ClosedDate IS NOT NULL AND COALESCE(phd.TotalReopenedEvents, 0) > 0 THEN 'ClosedAndReopened'
        WHEN pca.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pca.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
        WHEN pca.CommentCount > 5 AND COALESCE(pca.AnswerCount, 0) = 0 THEN 'DiscussionButNoAnswer'
        WHEN pca.HoursSinceLastActivity > 720 THEN 'Stale'
        ELSE 'Active'
    END AS PostStatus,
    -- Correlated Subquery: Check if the user has a 'Great Answer' badge (Class 2)
    EXISTS (SELECT 1 FROM Badges AS b WHERE b.UserId = ues.UserId AND b.Name = 'Great Answer' AND b.Class = 2) AS HasGreatAnswerBadge,
    -- CTE for top tags, then aggregate into a string, using a subquery to find top 3 tags for *this specific post*
    (
        SELECT STRING_AGG(tt.TagName, ', ' ORDER BY tt.TagUsage DESC)
        FROM (
            SELECT TagName, COUNT(*) AS TagUsage
            FROM TopTagsPerPost AS ttp
            WHERE ttp.PostId = pca.PostId
            GROUP BY TagName
            ORDER BY TagUsage DESC
            LIMIT 3
        ) AS tt
    ) AS Top3TagsForPost,
    -- Another window function: Calculate cumulative view count by user and creation date
    SUM(pca.ViewCount) OVER (PARTITION BY ues.UserId ORDER BY pca.PostCreationDate) AS CumulativeUserViews
FROM UserEngagementSummary AS ues
INNER JOIN PostContentAnalysis AS pca ON ues.UserId = pca.OwnerUserId
LEFT JOIN PostHistoryDetails AS phd ON pca.PostId = phd.PostId
LEFT JOIN PostLinkAnalysis AS pla ON pca.PostId = pla.PostId
WHERE ues.Reputation > 5000 -- Filter for reasonably reputable users
  AND pca.Score >= 50 -- Filter for highly scored posts
  AND pca.ViewCount >= 1000 -- Filter for well-viewed posts
  AND pca.HoursSinceLastActivity < 720 -- Posts active in the last month (less than 30 days old activity)
  AND (pca.FavoriteCount IS NULL OR pca.FavoriteCount >= 5) -- Posts with at least 5 favorites or no favorite data (implies active questions)
  -- More complex predicate using NULL logic, OR/AND, and combining CTE results
  AND (
      (COALESCE(phd.TotalEditEvents, 0) >= 3 AND COALESCE(phd.DistinctHistoryTypes, 0) >= 2) -- Posts with significant edits and diverse history
      OR
      (COALESCE(pla.DuplicatePostsCount, 0) > 0 AND COALESCE(pla.LinkedPostsCount, 0) > 0) -- Posts that are duplicates AND linked
      OR
      (pca.PostTypeId = 1 AND pca.AcceptedAnswerScore IS NULL AND COALESCE(pca.AnswerCount, 0) > 0 AND pca.CommentCount > 3) -- Question with answers but no accepted answer, and active discussion
  )
  AND ues.LastGoldBadgeDate IS NOT NULL -- User has at least one gold badge
ORDER BY EngagementIndex DESC, ues.Reputation DESC, pca.PostCreationDate DESC
LIMIT 500;
