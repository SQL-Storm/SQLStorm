-- {"query": "1676.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3211} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViewCount,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (60 * 60 * 24) AS DaysSinceCreation,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS ModerationCloseDeleteLockProtectEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS ModerationReopenUndeleteUnlockUnprotectEvents
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
FilteredAndAggregatedPosts AS (
    -- Group 1: High-scoring questions from the last 2 years, excluding community-owned
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.CommunityOwnedDate,
        'HighScoreQuestion' AS PostCategory
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 50
      AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 year')
      AND p.CommunityOwnedDate IS NULL

    UNION ALL

    -- Group 2: Recently edited answers from highly reputed users, potentially linked to other posts
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.CommunityOwnedDate,
        'RecentEditedAnswer' AS PostCategory
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts
    WHERE p.PostTypeId = 2
      AND p.LastEditDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
      AND u.Reputation >= 5000
),
PostEngagementMetrics AS (
    SELECT
        fap.PostId,
        fap.PostTypeId,
        fap.OwnerUserId,
        fap.PostCreationDate,
        fap.PostScore,
        fap.PostViewCount,
        fap.AnswerCount,
        fap.CommentCount,
        fap.FavoriteCount,
        COALESCE(fap.AnswerCount, 0) * 2 + COALESCE(fap.CommentCount, 0) * 1 + COALESCE(fap.FavoriteCount, 0) * 3 + COALESCE(fap.PostViewCount, 0) * 0.05 AS EngagementScore,
        TRIM(SUBSTRING(fap.Tags FROM 2 FOR LENGTH(fap.Tags) - 2)) AS RawTags, -- remove surrounding <> and trim
        LOWER(COALESCE(fap.Title, '')) AS LowerTitle,
        fap.ClosedDate,
        fap.CommunityOwnedDate,
        LAG(fap.PostScore, 1, 0) OVER (PARTITION BY fap.OwnerUserId ORDER BY fap.PostCreationDate) AS PrevPostScore,
        ROW_NUMBER() OVER (PARTITION BY fap.OwnerUserId ORDER BY fap.PostCreationDate DESC) AS rn_latest_post,
        -- Correlated subquery example: Check if this post is a duplicate of a more popular post
        EXISTS (
            SELECT 1
            FROM PostLinks pl_sub
            JOIN Posts related_p ON pl_sub.RelatedPostId = related_p.Id
            WHERE pl_sub.PostId = fap.PostId AND pl_sub.LinkTypeId = 3 -- Duplicate link type
              AND related_p.Score > fap.PostScore * 1.5 -- More popular
              AND related_p.CreationDate < fap.PostCreationDate -- Older post
        ) AS HasMorePopularDuplicate,
        fap.PostCategory
    FROM FilteredAndAggregatedPosts fap
),
ModerationEventDetails AS (
    SELECT
        ph.PostId,
        ph.UserId AS ModeratorOrVoterId,
        ph.CreationDate AS HistoryCreationDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_mod_event,
        FIRST_VALUE(crt.Name) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS LatestCloseReasonName,
        LAST_VALUE(ph.UserId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS FirstModeratorUserId
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
),
TopTagsPerPost AS (
    SELECT
        pem.PostId,
        pem.OwnerUserId,
        TRIM(UNNEST(string_to_array(pem.RawTags, '><'))) AS TagName -- Splits tags like <tag1><tag2> into 'tag1', 'tag2'
    FROM PostEngagementMetrics pem
    WHERE pem.RawTags IS NOT NULL AND LENGTH(pem.RawTags) > 0
),
PostTagPerformance AS (
    SELECT
        ttp.PostId,
        ttp.OwnerUserId,
        ttp.TagName,
        t.Count AS TagGlobalCount,
        ROW_NUMBER() OVER (PARTITION BY ttp.PostId ORDER BY t.Count DESC, ttp.TagName ASC) AS rn_tag_priority
    FROM TopTagsPerPost ttp
    JOIN Tags t ON ttp.TagName = t.TagName
    WHERE ttp.TagName IS NOT NULL AND ttp.TagName != ''
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.DaysSinceCreation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uas.TotalBadges,
    uas.TotalPostScore,
    uas.AvgPostViewCount,
    uas.ModerationCloseDeleteLockProtectEvents,
    uas.ModerationReopenUndeleteUnlockUnprotectEvents,
    -- Post-specific metrics for the latest post
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.PostId END) AS LatestPostId,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.PostCreationDate END) AS LatestPostDate,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.PostScore END) AS LatestPostScore,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.EngagementScore END) AS LatestPostEngagementScore,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.HasMorePopularDuplicate END) AS LatestPostIsDuplicateOfPopular,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.PostCategory END) AS LatestPostCategory,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN
        (SELECT COUNT(DISTINCT pl_sub.RelatedPostId) FROM PostLinks pl_sub WHERE pl_sub.PostId = pem.PostId AND pl_sub.LinkTypeId = 1)
    END) AS LatestPostLinkedCount,
    MAX(CASE WHEN pem.rn_latest_post = 1 THEN
        COALESCE(
            (SELECT MAX(ph_sub.CreationDate)
             FROM PostHistory ph_sub
             WHERE ph_sub.PostId = pem.PostId AND ph_sub.PostHistoryTypeId IN (4, 5, 6)
            ), NULL)
    END) AS LatestPostLastEditDate,
    -- Overall moderation status for user's posts
    COUNT(DISTINCT CASE WHEN med.PostHistoryTypeId = 10 THEN med.PostId END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN med.PostHistoryTypeId = 11 THEN med.PostId END) AS TotalReopenedPosts,
    COUNT(DISTINCT CASE WHEN med.PostHistoryTypeId = 19 THEN med.PostId END) AS TotalProtectedPosts,
    -- Window function over a user's posts to find the score trend
    AVG(pem.PrevPostScore) OVER (PARTITION BY uas.UserId) AS AvgPreviousPostScore,
    NTILE(5) OVER (ORDER BY uas.Reputation DESC, uas.TotalPostScore DESC) AS ReputationQuintile,
    -- String manipulations and conditional logic
    LOWER(LEFT(TRIM(COALESCE(uas.DisplayName, '')) || '#####', 5)) AS DisplayNamePrefix, -- Ensure 5 chars
    CASE
        WHEN uas.Reputation > 10000 AND uas.TotalQuestions > 50 THEN 'HighRep-ProlificQ'
        WHEN uas.Reputation > 5000 AND uas.TotalAnswers > 100 THEN 'MidRep-AnswerGuru'
        WHEN uas.ModerationCloseDeleteLockProtectEvents > uas.ModerationReopenUndeleteUnlockUnprotectEvents * 2 THEN 'ModerationTrouble'
        WHEN uas.DaysSinceCreation < 365 AND uas.TotalPosts > 10 AND uas.AvgPostViewCount > 500 THEN 'Newbie-ActiveAndPopular'
        ELSE 'Regular'
    END AS UserProfileCategory,
    -- Join with Tags via PostTagPerformance
    STRING_AGG(DISTINCT ptp.TagName, ', ') FILTER (WHERE ptp.rn_tag_priority = 1) AS MostFrequentTagsOfPosts,
    -- Example of NULL logic and complex expression in SELECT
    COALESCE(AVG(CASE WHEN pem.ClosedDate IS NOT NULL THEN EXTRACT(DAY FROM (pem.ClosedDate - pem.PostCreationDate)) ELSE NULL END), -1.0) AS AvgDaysToClose,
    -- Correlated subquery: Get the latest comment text for the user's latest post by themselves
    (SELECT c_sub.Text
     FROM Comments c_sub
     WHERE c_sub.PostId = MAX(CASE WHEN pem.rn_latest_post = 1 THEN pem.PostId END)
       AND c_sub.UserId = uas.UserId -- comment by the user themselves
     ORDER BY c_sub.CreationDate DESC
     LIMIT 1
    ) AS LatestUserCommentOnLatestPost
FROM UserActivitySummary uas
LEFT JOIN PostEngagementMetrics pem ON uas.UserId = pem.OwnerUserId
LEFT JOIN ModerationEventDetails med ON pem.PostId = med.PostId AND med.rn_latest_mod_event = 1
LEFT JOIN PostTagPerformance ptp ON pem.PostId = ptp.PostId AND ptp.rn_tag_priority = 1
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.DaysSinceCreation, uas.TotalPosts, uas.TotalQuestions,
    uas.TotalAnswers, uas.TotalComments, uas.TotalBadges, uas.TotalPostScore, uas.AvgPostViewCount,
    uas.ModerationCloseDeleteLockProtectEvents, uas.ModerationReopenUndeleteUnlockUnprotectEvents
HAVING
    uas.Reputation > 100
    AND (
        COUNT(DISTINCT CASE WHEN med.PostHistoryTypeId = 10 THEN med.PostId END) > 0
        OR uas.TotalQuestions > 5
        OR uas.TotalBadges >= 5
        OR uas.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '6 month')
    )
ORDER BY
    uas.Reputation DESC, LatestPostEngagementScore DESC NULLS LAST
LIMIT 100;
