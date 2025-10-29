-- {"query": "1301.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4284} 
WITH UserActivitySummary AS (
    -- Summarize user-specific post and basic activity statistics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalPostFavorites,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL AND EXISTS (SELECT 1 FROM Posts q WHERE q.Id = p.ParentId AND q.AcceptedAnswerId = p.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
UserCommentMetrics AS (
    -- Summarize user-specific comment statistics
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteInfluence AS (
    -- Summarize votes received on posts owned by each user
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS UpvotesReceivedOnPosts,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS DownvotesReceivedOnPosts,
        COUNT(DISTINCT v.PostId) AS PostsVotedOnByOthers
    FROM Posts AS p
    INNER JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeAchievements AS (
    -- Summarize user badge counts
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeAwardDate
    FROM Badges AS b
    GROUP BY b.UserId
),
PostRevisionDetails AS (
    -- Calculate revision counts and types for each post
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalRevisions,
        MAX(ph.CreationDate) AS LatestRevisionDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS MajorEditsCount, -- Edit/Rollback Title/Body/Tags
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS ModerationEventsCount -- Closed/Deleted/Locked/Protected
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
LinkedPostAggregates AS (
    -- Calculate average score of linked posts for each of a user's questions (correlated subquery logic applied per question)
    SELECT
        q.OwnerUserId AS UserId,
        q.Id AS QuestionId,
        (
            SELECT AVG(p_linked.Score)
            FROM PostLinks AS pl
            INNER JOIN Posts AS p_linked ON pl.RelatedPostId = p_linked.Id
            WHERE pl.PostId = q.Id AND p_linked.PostTypeId = 1 -- Only consider questions that are linked
        ) AS AvgLinkedQuestionScore,
        (
            SELECT COUNT(pl.Id)
            FROM PostLinks AS pl
            WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3 -- Count duplicate links
        ) AS DuplicateLinkCount
    FROM Posts AS q
    WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
),
AggregatedLinkedPostStats AS (
    -- Aggregate the linked post scores and counts per user
    SELECT
        UserId,
        AVG(AvgLinkedQuestionScore) AS OverallAvgLinkedQuestionScore,
        SUM(DuplicateLinkCount) AS TotalDuplicateLinksAsSource
    FROM LinkedPostAggregates
    GROUP BY UserId
)
-- Main query to combine all the information and apply advanced logic
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    COALESCE(uas.UserProfileViews, 0) AS UserProfileViews,
    COALESCE(uas.TotalPosts, 0) AS TotalPosts,
    COALESCE(uas.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(uas.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(uas.TotalPostViews, 0) AS TotalPostViews,
    COALESCE(uas.TotalPostFavorites, 0) AS TotalPostFavorites,
    COALESCE(uas.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(uas.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven,
    COALESCE(ucm.TotalComments, 0) AS TotalComments,
    COALESCE(ucm.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(uvi.UpvotesReceivedOnPosts, 0) AS UpvotesReceivedOnPosts,
    COALESCE(uvi.DownvotesReceivedOnPosts, 0) AS DownvotesReceivedOnPosts,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - uas.LastAccessDate)) AS DaysSinceLastAccess,
    (uas.Reputation + COALESCE(uba.GoldBadges * 100, 0) + COALESCE(uba.SilverBadges * 50, 0) + COALESCE(uba.BronzeBadges * 10, 0)) AS AdjustedInfluenceScore,
    CASE
        WHEN uas.Reputation > 10000 AND COALESCE(uba.GoldBadges, 0) >= 3 THEN 'Legendary Contributor'
        WHEN uas.Reputation > 5000 AND COALESCE(uba.GoldBadges, 0) >= 1 THEN 'High-Tier Expert'
        WHEN uas.Reputation > 1000 AND COALESCE(uba.SilverBadges, 0) >= 3 THEN 'Mid-Tier Veteran'
        WHEN uas.Reputation > 200 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS UserEngagementTier,
    COALESCE(alas.OverallAvgLinkedQuestionScore, 0.0) AS AvgScoreOfLinkedQuestions,
    COALESCE(alas.TotalDuplicateLinksAsSource, 0) AS TotalDuplicateLinksOrigin,
    RANK() OVER (ORDER BY uas.Reputation DESC, COALESCE(uvi.UpvotesReceivedOnPosts, 0) DESC, COALESCE(uba.GoldBadges, 0) DESC, COALESCE(uas.UserProfileViews, 0) DESC) AS GlobalUserRank,
    NTILE(10) OVER (ORDER BY (COALESCE(uas.TotalPostScore, 0) + COALESCE(ucm.TotalCommentScore, 0) + COALESCE(uvi.UpvotesReceivedOnPosts, 0)) DESC) AS TopScoreDecile,
    -- String expressions and NULL logic
    UPPER(LEFT(COALESCE(u.DisplayName, 'ANONYMOUS'), 3)) AS DisplayNamePrefix,
    LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
    COALESCE(u.Location, 'Unspecified') AS UserLocation,
    (COALESCE(uas.TotalPostScore, 0) + COALESCE(ucm.TotalCommentScore, 0) + COALESCE(uvi.UpvotesReceivedOnPosts, 0) - COALESCE(uvi.DownvotesReceivedOnPosts, 0)) / NULLIF(COALESCE(uas.TotalPosts, 0) + COALESCE(ucm.TotalComments, 0), 0) AS NetContentApprovalRatio,
    -- Aggregated revision info for their questions and answers
    SUM(CASE WHEN p.PostTypeId = 1 THEN prd.TotalRevisions ELSE 0 END) AS TotalQuestionRevisions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN prd.TotalRevisions ELSE 0 END) AS TotalAnswerRevisions,
    MAX(CASE WHEN p.PostTypeId = 1 THEN prd.LatestRevisionDate ELSE NULL END) AS LatestQuestionRevisionDate,
    MAX(CASE WHEN p.PostTypeId = 2 THEN prd.LatestRevisionDate ELSE NULL END) AS LatestAnswerRevisionDate,
    SUM(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsCount,
    SUM(CASE WHEN p.Tags LIKE '%<sql>%' AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS SQLQuestionsCount
FROM Users AS u
INNER JOIN UserActivitySummary AS uas ON u.Id = uas.UserId
LEFT JOIN UserCommentMetrics AS ucm ON u.Id = ucm.UserId
LEFT JOIN UserVoteInfluence AS uvi ON u.Id = uvi.UserId
LEFT JOIN UserBadgeAchievements AS uba ON u.Id = uba.UserId
LEFT JOIN AggregatedLinkedPostStats AS alas ON u.Id = alas.UserId
LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId -- Join to Posts again for revision details aggregation per user
LEFT JOIN PostRevisionDetails AS prd ON p.Id = prd.PostId
WHERE
    uas.Reputation > 500
    AND uas.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
    AND (u.WebsiteUrl IS NOT NULL OR u.Location LIKE '%developer%' OR u.Location IS NULL)
    AND LENGTH(COALESCE(u.AboutMe, '')) > 100 -- Ensure users have substantial 'AboutMe'
    AND (COALESCE(uas.TotalQuestions, 0) > 2 OR COALESCE(uas.TotalAnswers, 0) > 5)
    AND u.Id IN ( -- Non-correlated subquery: Filter users who have engaged with high-view posts
        SELECT p_high_view.OwnerUserId
        FROM Posts AS p_high_view
        WHERE p_high_view.PostTypeId IN (1,2)
        AND p_high_view.ViewCount > 10000
        AND p_high_view.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year'
        GROUP BY p_high_view.OwnerUserId
        HAVING COUNT(p_high_view.Id) >= 3
    )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.LastAccessDate,
    uas.UserProfileViews, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalPostScore, uas.TotalPostViews, uas.TotalPostFavorites,
    uas.QuestionsWithAcceptedAnswer, uas.AcceptedAnswersGiven,
    ucm.TotalComments, ucm.TotalCommentScore,
    uvi.UpvotesReceivedOnPosts, uvi.DownvotesReceivedOnPosts,
    uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges,
    alas.OverallAvgLinkedQuestionScore, alas.TotalDuplicateLinksAsSource,
    u.DisplayName, u.AboutMe, u.Location
HAVING
    (SUM(CASE WHEN p.PostTypeId = 1 THEN prd.TotalRevisions ELSE 0 END) > 5 -- Questions with many revisions
    OR SUM(CASE WHEN p.PostTypeId = 2 THEN prd.MajorEditsCount ELSE 0 END) > 2) -- Answers with many major edits
    AND COALESCE(alas.OverallAvgLinkedQuestionScore, 0.0) > 5.0 -- Linked to other good questions
    AND COALESCE(alas.TotalDuplicateLinksAsSource, 0) < 3 -- Not primarily source of duplicates
UNION ALL
-- Set operator: Identify users who are significant contributors to tag wikis
-- or are high-reputation users with no questions but many answers
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Views, 0) AS UserProfileViews,
    COALESCE(uas.TotalPosts, 0) AS TotalPosts,
    COALESCE(uas.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(uas.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(uas.TotalPostViews, 0) AS TotalPostViews,
    COALESCE(uas.TotalPostFavorites, 0) AS TotalPostFavorites,
    COALESCE(uas.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(uas.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven,
    COALESCE(ucm.TotalComments, 0) AS TotalComments,
    COALESCE(ucm.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(uvi.UpvotesReceivedOnPosts, 0) AS UpvotesReceivedOnPosts,
    COALESCE(uvi.DownvotesReceivedOnPosts, 0) AS DownvotesReceivedOnPosts,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - u.LastAccessDate)) AS DaysSinceLastAccess,
    (u.Reputation + COALESCE(uba.GoldBadges * 200, 0)) AS AdjustedInfluenceScore,
    'Specialized-Knowledge-Curator' AS UserEngagementTier,
    NULL AS AvgScoreOfLinkedQuestions,
    NULL AS TotalDuplicateLinksOrigin,
    NULL AS GlobalUserRank,
    NULL AS TopScoreDecile,
    UPPER(LEFT(COALESCE(u.DisplayName, 'ANONYMOUS'), 3)) AS DisplayNamePrefix,
    LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
    COALESCE(u.Location, 'Unspecified') AS UserLocation,
    (COALESCE(uas.TotalPostScore, 0) + COALESCE(ucm.TotalCommentScore, 0) + COALESCE(uvi.UpvotesReceivedOnPosts, 0) - COALESCE(uvi.DownvotesReceivedOnPosts, 0)) / NULLIF(COALESCE(uas.TotalPosts, 0) + COALESCE(ucm.TotalComments, 0), 0) AS NetContentApprovalRatio,
    SUM(CASE WHEN p_wiki.PostTypeId IN (4,5) THEN prd_wiki.TotalRevisions ELSE 0 END) AS TotalQuestionRevisions, -- Re-use column name, but for wiki revisions
    0 AS TotalAnswerRevisions,
    MAX(CASE WHEN p_wiki.PostTypeId IN (4,5) THEN prd_wiki.LatestRevisionDate ELSE NULL END) AS LatestQuestionRevisionDate,
    NULL AS LatestAnswerRevisionDate,
    0 AS ClosedQuestionsCount,
    0 AS SQLQuestionsCount
FROM Users AS u
LEFT JOIN UserActivitySummary AS uas ON u.Id = uas.UserId
LEFT JOIN UserCommentMetrics AS ucm ON u.Id = ucm.UserId
LEFT JOIN UserVoteInfluence AS uvi ON u.Id = uvi.UserId
LEFT JOIN UserBadgeAchievements AS uba ON u.Id = uba.UserId
LEFT JOIN Posts AS p_wiki ON u.Id = p_wiki.OwnerUserId AND p_wiki.PostTypeId IN (4,5) -- TagWikiExcerpt or TagWiki
LEFT JOIN PostRevisionDetails AS prd_wiki ON p_wiki.Id = prd_wiki.PostId
WHERE
    (COALESCE(uas.TotalQuestions, 0) = 0 AND COALESCE(uas.TotalAnswers, 0) >= 10 AND u.Reputation > 2000) -- High rep, no questions, many answers
    OR (p_wiki.Id IS NOT NULL AND COALESCE(prd_wiki.TotalRevisions, 0) > 0) -- Has edited a Tag Wiki
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.AboutMe, u.Location,
    uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalPostScore, uas.TotalPostViews,
    uas.TotalPostFavorites, uas.QuestionsWithAcceptedAnswer, uas.AcceptedAnswersGiven,
    ucm.TotalComments, ucm.TotalCommentScore, uvi.UpvotesReceivedOnPosts, uvi.DownvotesReceivedOnPosts,
    uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges;