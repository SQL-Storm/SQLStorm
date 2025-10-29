-- {"query": "1754.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3038} 
WITH UserEngagementScores AS (
    -- Calculate a weighted engagement score for users based on posts, comments, and votes
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS SumPostScores,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        -- Weighted engagement score: Reputation + (Sum of post scores * 0.5) + (Total comments * 0.2) + (Upvotes * 0.1 - Downvotes * 0.05)
        (u.Reputation +
         COALESCE(SUM(p.Score), 0) * 0.5 +
         COUNT(DISTINCT c.Id) * 0.2 +
         u.UpVotes * 0.1 - u.DownVotes * 0.05
        ) AS WeightedEngagementScore,
        DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - u.LastAccessDate) AS DaysSinceLastAccess
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2015-01-01' -- Focus on more recent users for varied data
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 3 AND u.Reputation > 500
),
PostContentMetrics AS (
    -- Analyze post content and tags
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        -- Extract primary tag for analysis (or NULL if no tags)
        (SELECT TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) LIMIT 1) AS PrimaryTag,
        -- Determine post age in months
        DATE_PART('year', cast('2024-10-01 12:34:56' as timestamp)) * 12 + DATE_PART('month', cast('2024-10-01 12:34:56' as timestamp)) -
        (DATE_PART('year', p.CreationDate) * 12 + DATE_PART('month', p.CreationDate)) AS AgeInMonths,
        -- Check if post has a high comment-to-view ratio (potential for controversial/engaging posts)
        CASE WHEN p.ViewCount > 0 THEN CAST(p.CommentCount AS DECIMAL) / p.ViewCount ELSE 0 END AS CommentViewRatio
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year' -- Recent posts
    AND p.Score > 0 -- Only positive scored posts
),
TagQualityAggregates AS (
    -- Aggregate metrics for tags, including window functions for comparison
    SELECT
        pcm.PrimaryTag,
        COUNT(DISTINCT pcm.PostId) AS TagPostCount,
        AVG(pcm.Score) AS AvgTagScore,
        SUM(pcm.ViewCount) AS TotalTagViews,
        SUM(COALESCE(pcm.FavoriteCount, 0)) AS TotalTagFavorites,
        -- Average score for posts of this tag compared to overall average
        AVG(pcm.Score) - AVG(AVG(pcm.Score)) OVER () AS AvgScoreRelativeToOverall,
        -- Rank tags by their average score
        DENSE_RANK() OVER (ORDER BY AVG(pcm.Score) DESC) AS TagScoreRank
    FROM PostContentMetrics pcm
    WHERE pcm.PrimaryTag IS NOT NULL
    GROUP BY pcm.PrimaryTag
    HAVING COUNT(DISTINCT pcm.PostId) > 20 -- Significant tags
),
PostHistoryEvents AS (
    -- Union of specific, "significant" post history events
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        pht.Name AS EventTypeName,
        'Edit/Rollback' AS EventCategory,
        ph.UserId AS EventUserId,
        ph.Comment AS EventComment,
        LENGTH(ph.Text) AS TextChangeLength
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title, Body, Tags
    UNION ALL
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        pht.Name AS EventTypeName,
        'Lifecycle' AS EventCategory,
        ph.UserId AS EventUserId,
        COALESCE(cr.Name, ph.Comment) AS EventComment, -- If it's a close event, try to get CloseReasonType name
        NULL AS TextChangeLength
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cr ON
        ph.PostHistoryTypeId = 10
        AND ph.Comment IS NOT NULL AND ph.Comment ~ '^[0-9]+$' -- Regex to check if comment is a number
        AND CAST(ph.Comment AS SMALLINT) = cr.Id
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20) -- Close, Reopen, Delete, Undelete, Protect, Unprotect
),
UserLifetimeMetrics AS (
    -- Calculate cumulative metrics and identify badge milestones for users
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        LAG(b.Date, 1, b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS PreviousBadgeDate, -- LAG for time between badges
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn_latest_badge,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS CumulativeGoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS CumulativeSilverBadges
    FROM Badges b
    WHERE b.Class IN (1, 2) -- Gold and Silver badges only
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.WeightedEngagementScore,
    ues.DaysSinceLastAccess,
    ues.QuestionCount,
    ues.AnswerCount,
    pcm.PostId,
    pcm.Title AS PostTitle,
    pcm.PostCreationDate,
    pcm.Score AS PostScore,
    pcm.ViewCount AS PostViews,
    pcm.CommentViewRatio,
    pcm.PrimaryTag,
    tqa.AvgTagScore,
    tqa.TagScoreRank,
    COALESCE(ulm.BadgeName, 'No Gold/Silver Badge') AS LatestGoldSilverBadge,
    COALESCE(ulm.BadgeClass, 0) AS LatestBadgeClass,
    ulm.PreviousBadgeDate AS DateOfPreviousBadge,
    ph_first_close.EventDate AS FirstCloseDate,
    ph_last_reopen.EventDate AS LastReopenDate,
    -- Correlated subquery: check if the post has any duplicates
    (SELECT EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pcm.PostId AND pl.LinkTypeId = 3)) AS HasDuplicates,
    -- Another correlated subquery: average score of answers for a question (if it's a question)
    -- Using NULLIF to prevent division by zero if there are no answers
    NULLIF((SELECT SUM(a.Score) FROM Posts a WHERE a.ParentId = pcm.PostId AND pcm.PostTypeId = 1), 0) /
    NULLIF((SELECT COUNT(a.Id) FROM Posts a WHERE a.ParentId = pcm.PostId AND pcm.PostTypeId = 1), 0) AS AvgAnswerScoreForQuestion,
    -- Cumulative score for user's posts, ordered by creation date
    SUM(pcm.Score) OVER (PARTITION BY ues.UserId ORDER BY pcm.PostCreationDate) AS UserCumulativePostScore,
    -- Percentage of posts for this user that are questions vs. answers (using TotalPostsOwned from ues)
    CAST(ues.QuestionCount AS DECIMAL) / NULLIF(ues.TotalPostsOwned, 0) AS QuestionRatio,
    -- Complex string expression: User's DisplayName + " (" + PrimaryTag of post + ")"
    ues.DisplayName || ' (' || COALESCE(pcm.PrimaryTag, 'untagged') || ')' AS UserTagIdentifier,
    CASE
        WHEN ues.WeightedEngagementScore > 5000 AND tqa.TagScoreRank <= 10 THEN 'Elite Contributor in Top Tag'
        WHEN ues.WeightedEngagementScore > 1000 AND tqa.AvgTagScore > 10 THEN 'Valued Tag Contributor'
        WHEN ues.DaysSinceLastAccess > 30 AND ues.DaysSinceLastAccess <= 180 THEN 'Dormant Engaged User'
        WHEN ues.DaysSinceLastAccess > 180 THEN 'Inactive User'
        ELSE 'Active User'
    END AS UserPersonaClassification,
    -- Nested COALESCE for a 'post status' field that combines multiple sources
    COALESCE(
        (SELECT 'Closed' FROM PostHistoryEvents phe WHERE phe.PostId = pcm.PostId AND phe.EventTypeName LIKE '%Closed%' LIMIT 1),
        (SELECT 'Deleted' FROM PostHistoryEvents phe WHERE phe.PostId = pcm.PostId AND phe.EventTypeName LIKE '%Deleted%' LIMIT 1),
        'Open/Active'
    ) AS PostCurrentStatus,
    -- Calculate a "Post Health Index"
    (pcm.Score * 0.7 + pcm.ViewCount * 0.001 + pcm.CommentViewRatio * 100 + COALESCE(pcm.FavoriteCount, 0) * 0.5) *
    (CASE WHEN ph_first_close.EventDate IS NOT NULL THEN 0.5 -- Penalize closed posts
          WHEN ph_last_reopen.EventDate IS NOT NULL THEN 0.8 -- Slightly less penalty for reopened posts
          ELSE 1 END) AS PostHealthIndex,
    -- Day of week when the post was created (0=Sunday, 6=Saturday)
    EXTRACT(DOW FROM pcm.PostCreationDate) AS CreationDayOfWeek,
    -- Check if user's location contains "remote" or "online"
    (SELECT u_loc.Location LIKE '%remote%' OR u_loc.Location LIKE '%online%' FROM Users u_loc WHERE u_loc.Id = ues.UserId) AS IsRemoteUserLocation
FROM UserEngagementScores ues
JOIN PostContentMetrics pcm ON ues.UserId = pcm.OwnerUserId
LEFT JOIN TagQualityAggregates tqa ON pcm.PrimaryTag = tqa.PrimaryTag
LEFT JOIN UserLifetimeMetrics ulm ON ues.UserId = ulm.UserId AND ulm.rn_latest_badge = 1 -- Get the latest Gold/Silver badge info
LEFT JOIN (
    SELECT PostId, MIN(EventDate) AS EventDate
    FROM PostHistoryEvents
    WHERE EventCategory = 'Lifecycle' AND EventTypeName LIKE '%Closed%'
    GROUP BY PostId
) AS ph_first_close ON pcm.PostId = ph_first_close.PostId
LEFT JOIN (
    SELECT PostId, MAX(EventDate) AS EventDate
    FROM PostHistoryEvents
    WHERE EventCategory = 'Lifecycle' AND EventTypeName LIKE '%Reopened%'
    GROUP BY PostId
) AS ph_last_reopen ON pcm.PostId = ph_last_reopen.PostId
WHERE ues.DaysSinceLastAccess <= 180 -- Users active in last 6 months
  AND pcm.AgeInMonths BETWEEN 1 AND 24 -- Posts from last two years
  AND pcm.PostTypeId = 1 -- Focus on questions for more complexity
  AND pcm.BodyLength > 100 -- Meaningful post bodies
ORDER BY ues.WeightedEngagementScore DESC, pcm.PostCreationDate DESC
LIMIT 500;