-- {"query": "1036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2703} 
WITH UserActivityMetrics AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreOwned,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViewCountOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(u.LastAccessDate) AS LastActivityDate,
        MIN(u.CreationDate) AS UserCreationDate,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS ClosedQuestionsOwned,
        SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedPostsOwned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.Views, u.CreationDate
),
PostVoteSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.OwnerUserId
),
PostTagPerformance AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        TRIM(t.TagName) AS TagName, -- Trim whitespace from tag names
        AVG(p.Score) OVER (PARTITION BY TRIM(t.TagName)) AS AvgTagScore,
        DENSE_RANK() OVER (PARTITION BY TRIM(t.TagName) ORDER BY p.Score DESC, p.CreationDate) AS RankInTagByScore
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS t(TagName)
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only questions for tag performance analysis
),
UserModerationActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN ph.PostId END) AS PostsModeratedCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN ph.PostId END) AS PostsUnmoderatedCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1 ELSE 0 END) AS DuplicateCloseVotesInitiated, -- Assuming comment is CloseReasonId 101 for duplicate
        MAX(ph.CreationDate) AS LastModerationActionDate
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) -- Various moderation/migration actions
    GROUP BY ph.UserId
),
TopQuestionContributors AS (
    SELECT
        p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND ViewCount IS NOT NULL) * 2 -- Double the average view count
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND Score IS NOT NULL) * 1.5 -- 1.5 times the average score
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) >= 3 -- At least 3 highly viewed/scored questions
),
TopAnswerContributors AS (
    SELECT
        p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2 AND Score IS NOT NULL) * 2 -- Double the average score for answers
    AND p.AcceptedAnswerId IS NOT NULL -- Was accepted
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) >= 5 -- At least 5 highly scored and accepted answers
),
HighlyEngagedUsers AS (
    SELECT UserId, 'Questioner' AS EngagementType FROM TopQuestionContributors
    UNION ALL
    SELECT UserId, 'Answerer' AS EngagementType FROM TopAnswerContributors
),
UserContentActivity AS (
    SELECT
        uam.UserId,
        uam.Reputation,
        uam.TotalPostsOwned,
        uam.TotalQuestionsOwned,
        uam.TotalAnswersOwned,
        uam.TotalPostScoreOwned,
        uam.AvgPostViewCountOwned,
        uam.TotalCommentsMade,
        uam.TotalBadgesEarned,
        uam.LastActivityDate,
        uam.UserCreationDate,
        uam.ClosedQuestionsOwned,
        uam.CommunityOwnedPostsOwned,
        COALESCE(SUM(ps.UpVotesReceived), 0) AS UserTotalUpVotesReceived,
        COALESCE(SUM(ps.DownVotesReceived), 0) AS UserTotalDownVotesReceived,
        COALESCE(SUM(ps.FavoritesReceived), 0) AS UserTotalFavoritesReceived,
        COALESCE(uma.PostsModeratedCount, 0) AS TotalPostsModerated,
        COALESCE(uma.PostsUnmoderatedCount, 0) AS TotalPostsUnmoderated,
        COALESCE(uma.DuplicateCloseVotesInitiated, 0) AS TotalDuplicateCloseVotesInitiated,
        STRING_AGG(DISTINCT heu.EngagementType, ', ') FILTER (WHERE heu.EngagementType IS NOT NULL) AS EngagementRoles,
        COUNT(DISTINCT heu.EngagementType) AS DistinctEngagementRolesCount,
        SUM(CASE WHEN ppf.Score > ppf.AvgTagScore THEN 1 ELSE 0 END) AS AboveAvgTagScorePosts,
        MAX(ppf.RankInTagByScore) FILTER (WHERE ppf.RankInTagByScore <= 5) AS MaxTop5RankInAnyTag
    FROM UserActivityMetrics uam
    LEFT JOIN PostVoteSummary ps ON uam.UserId = ps.OwnerUserId
    LEFT JOIN UserModerationActivity uma ON uam.UserId = uma.UserId
    LEFT JOIN HighlyEngagedUsers heu ON uam.UserId = heu.UserId
    LEFT JOIN PostTagPerformance ppf ON uam.UserId = ppf.OwnerUserId
    GROUP BY
        uam.UserId, uam.Reputation, uam.TotalPostsOwned, uam.TotalQuestionsOwned, uam.TotalAnswersOwned,
        uam.TotalPostScoreOwned, uam.AvgPostViewCountOwned, uam.TotalCommentsMade, uam.TotalBadgesEarned,
        uam.LastActivityDate, uam.UserCreationDate, uam.ClosedQuestionsOwned, uam.CommunityOwnedPostsOwned,
        uma.PostsModeratedCount, uma.PostsUnmoderatedCount, uma.DuplicateCloseVotesInitiated
)
SELECT
    uca.UserId,
    u.DisplayName,
    uca.Reputation,
    uca.TotalPostsOwned,
    uca.TotalQuestionsOwned,
    uca.TotalAnswersOwned,
    uca.TotalCommentsMade,
    uca.TotalBadgesEarned,
    uca.UserTotalUpVotesReceived,
    uca.UserTotalDownVotesReceived,
    uca.TotalPostsModerated,
    uca.TotalDuplicateCloseVotesInitiated,
    uca.EngagementRoles,
    uca.DistinctEngagementRolesCount,
    uca.AboveAvgTagScorePosts,
    uca.MaxTop5RankInAnyTag,
    EXTRACT(DAY FROM (uca.LastActivityDate - uca.UserCreationDate)) AS DaysActiveSinceCreation,
    CASE
        WHEN uca.Reputation > 20000 AND uca.TotalQuestionsOwned > 50 AND uca.UserTotalUpVotesReceived > 1000 THEN 'High-Impact Author'
        WHEN uca.TotalBadgesEarned >= 10 AND uca.TotalPostsModerated > 5 AND uca.TotalCommentsMade > 50 THEN 'Community Champion'
        WHEN uca.TotalDuplicateCloseVotesInitiated > 10 AND uca.TotalPostsOwned < 20 THEN 'Voter Focus'
        WHEN uca.UserTotalDownVotesReceived > 200 AND uca.TotalPostsOwned > 50 AND uca.ClosedQuestionsOwned > 0 THEN 'Critical Contributor'
        WHEN uca.MaxTop5RankInAnyTag IS NOT NULL THEN 'Niche Expert'
        WHEN uca.DistinctEngagementRolesCount > 1 THEN 'Versatile Contributor'
        ELSE 'General Contributor'
    END AS UserCategory,
    -- Correlated subquery: Find the DisplayName of the last known editor (not the owner) for any of their posts
    (
        SELECT
            COALESCE(ph_inner.UserDisplayName, 'Community User')
        FROM PostHistory ph_inner
        WHERE ph_inner.PostId IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = uca.UserId)
          AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
          AND ph_inner.UserId IS NOT NULL
          AND ph_inner.UserId <> uca.UserId -- Editor is not the owner
        ORDER BY ph_inner.CreationDate DESC
        LIMIT 1
    ) AS LastKnownExternalEditorOfTheirPosts,
    -- Correlated subquery: Count how many of their questions have been linked as duplicates
    (
        SELECT COUNT(DISTINCT pl_inner.RelatedPostId)
        FROM PostLinks pl_inner
        WHERE pl_inner.PostId IN (SELECT p_link.Id FROM Posts p_link WHERE p_link.OwnerUserId = uca.UserId AND p_link.PostTypeId = 1)
          AND pl_inner.LinkTypeId = 3 -- Duplicate
    ) AS QuestionsLinkedAsDuplicateCount,
    LOWER(COALESCE(u.Location, '')) LIKE '%london%' OR LOWER(COALESCE(u.Location, '')) LIKE '%uk%' AS IsUKBasedUser,
    COALESCE(u.WebsiteUrl, 'NO_WEBSITE_PROVIDED') AS WebsiteStatus
FROM UserContentActivity uca
JOIN Users u ON uca.UserId = u.Id
WHERE uca.Reputation > 1000
  AND (uca.TotalPostsOwned > 10 OR uca.TotalCommentsMade > 20 OR uca.TotalBadgesEarned > 5)
  AND uca.LastActivityDate > (NOW() - INTERVAL '1 year') -- Only active in the last year
ORDER BY uca.Reputation DESC, uca.TotalPostsOwned DESC, uca.UserTotalUpVotesReceived DESC
LIMIT 500;