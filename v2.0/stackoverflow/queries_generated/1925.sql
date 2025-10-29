-- {"query": "1925.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3140} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(p.AnswerCount), 0) AS TotalAnswersReceived,
        COALESCE(SUM(p.CommentCount), 0) AS TotalCommentsOnPosts,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoritesOnPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScoreReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalPostUpVotesReceived,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalPostDownVotesReceived,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalAcceptedAnswers,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS TotalFavoritesByOthers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes pv ON p.Id = pv.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostContentMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        LENGTH(p.Title) AS TitleLength,
        LENGTH(p.Body) AS BodyLength,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        COALESCE(AVG(c.Score), 0.0) AS AverageCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        -- Correlated subquery: Get the highest score of an accepted answer if it's a question
        (SELECT MAX(pa.Score) FROM Posts pa WHERE pa.Id = p.AcceptedAnswerId AND p.PostTypeId = 1) AS AcceptedAnswerMaxScore,
        -- Correlated subquery: Calculate the number of distinct editors for the post
        (SELECT COUNT(DISTINCT ph.UserId)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title/Body/Tags
           AND ph.UserId IS NOT NULL
        ) AS DistinctEditorCount,
        -- Window function: Rank posts by score within each post type
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostTypeScoreRank,
        -- Window function: Calculate average score of all posts by the same owner, up to this post's creation date
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RunningAvgOwnerPostScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
        p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.Title, p.Body
),
TagAnalysis AS (
    SELECT
        p.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
),
PostModerationHistory AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate, -- Post Closed
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate, -- Post Reopened
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN ph.UserId ELSE NULL END) AS LastModeratorActionUserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenCount,
        ARRAY_AGG(DISTINCT crt.Name) FILTER (WHERE ph.PostHistoryTypeId = 10 AND crt.Name IS NOT NULL) AS CloseReasonNames
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::varchar(50)
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY ph.PostId
),
-- Set operator CTE: Identify users who have authored questions but no answers
QuestionOnlyUsers AS (
    SELECT DISTINCT OwnerUserId AS UserId FROM Posts WHERE PostTypeId = 1
    EXCEPT
    SELECT DISTINCT OwnerUserId AS UserId FROM Posts WHERE PostTypeId = 2
)
-- Main query combining all CTEs and applying complex logic
SELECT
    uas.UserId,
    COALESCE(uas.DisplayName, 'Deleted User (' || uas.UserId || ')') AS UserDisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.TotalPostViews,
    uas.TotalCommentsMade,
    uas.TotalBadges,
    (uas.TotalPostUpVotesReceived - uas.TotalPostDownVotesReceived) AS NetPostVotesReceived,
    -- Complicated calculation: Calculate a "User Influence Score"
    (uas.Reputation * 0.5) + (uas.TotalPostScore * 0.2) + (uas.TotalCommentsMade * 0.1) + (uas.TotalBadges * 1.0) + (uas.TotalFavoritesOnPosts * 0.3) AS UserInfluenceScore,

    -- Window function: Rank users by their Influence Score globally
    DENSE_RANK() OVER (ORDER BY (uas.Reputation * 0.5) + (uas.TotalPostScore * 0.2) + (uas.TotalCommentsMade * 0.1) + (uas.TotalBadges * 1.0) + (uas.TotalFavoritesOnPosts * 0.3) DESC) AS GlobalInfluenceRank,

    -- Window function: Calculate the average reputation of users created in the same year
    AVG(uas.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM uas.UserCreationDate)) AS AvgReputationForCreationYear,

    -- Information about their most recent post
    MAX(p.Id) AS MostRecentPostId,
    MAX(p.CreationDate) AS MostRecentPostDate,
    MAX(pcm.PostTypeScoreRank) FILTER (WHERE p.Id = pcm.PostId) AS MostRecentPostTypeRank,

    -- Aggregate metrics for posts by this user
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL) AS ClosedQuestionsCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND pcm.AcceptedAnswerMaxScore IS NOT NULL) AS AnswersToAcceptedQuestionsCount,
    AVG(pcm.AverageCommentScore) AS AvgCommentsScoreAcrossPosts,
    AVG(pcm.BodyLength) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionBodyLength,
    AVG(pcm.BodyLength) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerBodyLength,
    MAX(pcm.RunningAvgOwnerPostScore) AS MaxRunningAvgPostScore,

    -- Complicated predicate/expression: Identify users with potentially problematic content or high engagement from moderators
    CASE
        WHEN EXISTS (SELECT 1 FROM PostModerationHistory pmh WHERE pmh.PostId = p.Id AND pmh.CloseCount > 0)
             OR uas.TotalPostDownVotesReceived > uas.TotalPostUpVotesReceived * 0.5
        THEN 'Review Candidate'
        WHEN uas.TotalPosts > 100 AND uas.TotalBadges < 5 THEN 'Prolific but Low Recognition'
        ELSE 'Normal Contributor'
    END AS UserContentProfile,

    -- String expression: Analyze display name patterns
    CASE
        WHEN LOWER(uas.DisplayName) LIKE '%admin%' OR LOWER(uas.DisplayName) LIKE '%mod%' THEN 'Admin/Mod Related'
        WHEN LENGTH(uas.DisplayName) IS NOT NULL AND LENGTH(uas.DisplayName) < 5 THEN 'Short Name'
        ELSE 'Regular Name'
    END AS DisplayNameCategory,

    -- NULL Logic: How many posts by this user are community owned, if any?
    COALESCE(SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END), 0) AS CommunityOwnedPostsCount,

    -- Correlated Subquery in SELECT: Get the count of posts that are linked to any of this user's posts
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = uas.UserId)
          AND pl.LinkTypeId = 1
    ) AS LinkedPostsCount,

    -- Complicated predicate: Categorize users based on their post vote dynamics
    CASE
        WHEN uas.TotalPostUpVotesReceived > 0 AND uas.TotalPostDownVotesReceived = 0 THEN 'Only Upvoted'
        WHEN uas.TotalPostUpVotesReceived = 0 AND uas.TotalPostDownVotesReceived > 0 THEN 'Only Downvoted'
        WHEN uas.TotalPostUpVotesReceived > 0 AND uas.TotalPostDownVotesReceived > 0 THEN 'Mixed Votes'
        ELSE 'No Votes on Posts'
    END AS PostVoteCategory,

    -- NULL Logic: Use the result of the `EXCEPT` set operator
    CASE WHEN qo.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS IsQuestionOnlyUser,

    -- String expression: Aggregate distinct tags from user's posts
    ARRAY_AGG(DISTINCT ta.TagName ORDER BY ta.TagName) FILTER (WHERE ta.TagName IS NOT NULL) AS UserPostTags
FROM UserActivitySummary uas
LEFT JOIN Posts p ON uas.UserId = p.OwnerUserId
LEFT JOIN PostContentMetrics pcm ON p.Id = pcm.PostId
LEFT JOIN TagAnalysis ta ON p.Id = ta.PostId
LEFT JOIN PostModerationHistory pmh ON p.Id = pmh.PostId
LEFT JOIN QuestionOnlyUsers qo ON uas.UserId = qo.UserId
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.LastAccessDate,
    uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalPostScore, uas.TotalPostViews,
    uas.TotalCommentsMade, uas.TotalBadges, uas.TotalPostUpVotesReceived, uas.TotalPostDownVotesReceived,
    uas.TotalFavoritesOnPosts, qo.UserId
HAVING
    -- Complicated predicate: Filter users who are active, have a decent reputation, and specific content patterns
    uas.Reputation > 500
    AND uas.TotalPosts > 5
    AND (
        (uas.TotalQuestions > 0 AND COALESCE(AVG(pcm.AverageCommentScore), 0) > 0.5) -- Users who ask questions and get good comments
        OR
        (uas.TotalAnswers > 0 AND COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL) > 0) -- Users who provide accepted answers
    )
    AND uas.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Active in the last year
ORDER BY UserInfluenceScore DESC, uas.Reputation DESC, uas.UserId ASC;
