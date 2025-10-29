-- {"query": "1820.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4799} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        -- Calculate average days between posts for a user, considering only posts made by them
        AVG(CASE WHEN p.OwnerUserId = u.Id THEN EXTRACT(DAY FROM (p.CreationDate - LAG(p.CreationDate) OVER (PARTITION BY u.Id ORDER BY p.CreationDate))) END) AS AvgDaysBetweenPosts,
        -- Count of unique tags used by the user in their questions
        COUNT(DISTINCT TRIM(SUBSTRING(unnest(string_to_array(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>')), 1, 50))) AS UniqueTagsUsed,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount, -- Number of times closed
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6) AND ph.UserId IS NOT NULL) AS UniqueEditors,
        SUM(COALESCE(cm.Score, 0)) AS SumCommentScores,
        COUNT(cm.Id) AS CommentCountActual,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        (SELECT COUNT(a.Id) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS ActualAnswerCount,
        -- Check for specific keywords in body and title
        CASE WHEN LOWER(p.Body) LIKE '%performance%' OR LOWER(p.Title) LIKE '%performance%' THEN 1 ELSE 0 END AS HasPerformanceKeyword,
        CASE WHEN LOWER(p.Tags) LIKE '%<sql>%' OR LOWER(p.Tags) LIKE '%<database>%' THEN 1 ELSE 0 END AS HasDatabaseTag
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments cm ON p.Id = cm.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.Body, p.Title, p.AcceptedAnswerId
),
TagUsageMetrics AS (
    SELECT
        TRIM(unnest(string_to_array(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>'))) AS TagName,
        COUNT(p.Id) AS TaggedPostsCount,
        AVG(p.Score) AS AvgScoreForTag,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueTagUsers,
        SUM(p.ViewCount) AS TotalTagViews,
        -- Get the user who posted the most questions for this tag (correlated subquery)
        (
            SELECT u.DisplayName
            FROM Posts sq_p
            JOIN Users u ON sq_p.OwnerUserId = u.Id
            WHERE sq_p.PostTypeId = 1 AND sq_p.Tags LIKE '%<' || TRIM(unnest(string_to_array(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>'))) || '>%'
            GROUP BY u.Id, u.DisplayName
            ORDER BY COUNT(sq_p.Id) DESC
            LIMIT 1
        ) AS TopTagContributorDisplayName
    FROM
        Posts p
    WHERE
        p.Tags IS NOT NULL AND p.PostTypeId = 1
    GROUP BY
        TRIM(unnest(string_to_array(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>')))
),
ConsolidatedPostData AS (
    SELECT
        pca.PostId,
        pca.PostTypeId,
        pca.OwnerUserId,
        pca.PostCreationDate,
        pca.Score,
        pca.ViewCount,
        pca.CommentCount,
        pca.FavoriteCount,
        pca.BodyLength,
        pca.TitleLength,
        pca.EditCount,
        pca.CloseVoteCount,
        pca.UniqueEditors,
        pca.SumCommentScores,
        pca.CommentCountActual,
        pca.AcceptedAnswerId,
        pca.ActualAnswerCount,
        pca.HasPerformanceKeyword,
        pca.HasDatabaseTag,
        -- Calculate a "Controversy Index"
        CAST(pca.EditCount AS DECIMAL) / NULLIF(pca.CommentCountActual, 0) AS EditToCommentRatio,
        CAST(pca.CloseVoteCount AS DECIMAL) / NULLIF(pca.EditCount + 1, 0) AS CloseToEditRatio, -- +1 to avoid division by zero
        -- A calculated "Post Engagement Score"
        (COALESCE(pca.Score,0) * 0.5 + COALESCE(pca.ViewCount,0) * 0.1 + COALESCE(pca.CommentCount,0) * 0.2 + COALESCE(pca.FavoriteCount,0) * 0.2) AS PostEngagementScore,
        -- Is this post "community owned"? Check if CommunityOwnedDate is not null.
        CASE WHEN p_base.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned,
        -- NTILE for grouping posts by their score into 4 quartiles
        NTILE(4) OVER (PARTITION BY pca.PostTypeId ORDER BY pca.Score DESC) AS ScoreQuartile
    FROM
        PostContentAnalysis pca
    JOIN Posts p_base ON pca.PostId = p_base.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.Views AS UserProfileViews,
    u.UpVotes AS UserUpVotesReceived,
    u.DownVotes AS UserDownVotesReceived,
    COALESCE(u.Location, 'N/A') AS UserLocation,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.TotalPostScore,
    us.TotalPostViews,
    us.TotalComments,
    us.TotalBadges,
    us.LastPostActivity,
    us.LastCommentActivity,
    us.AvgDaysBetweenPosts,
    us.UniqueTagsUsed,
    us.TotalUpVotesGiven,
    us.TotalDownVotesGiven,
    -- User Reputation Tier (1st quintile = top 20%)
    NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationTier,
    -- Overall average score for user's posts
    CAST(us.TotalPostScore AS DECIMAL) / NULLIF(us.TotalPosts, 0) AS AvgScorePerPost,
    -- Ratio of UpVotesGiven to DownVotesGiven
    CAST(us.TotalUpVotesGiven AS DECIMAL) / NULLIF(us.TotalDownVotesGiven + us.TotalUpVotesGiven, 0) AS UpVoteEngagementRatio,

    -- Information about the user's most recent question (if any)
    LAST_VALUE(cpd_q.PostId) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionId,
    LAST_VALUE(cpd_q.TitleLength) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionTitleLength,
    LAST_VALUE(cpd_q.PostEngagementScore) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionEngagementScore,
    LAST_VALUE(cpd_q.EditToCommentRatio) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionEditToCommentRatio,
    LAST_VALUE(cpd_q.HasPerformanceKeyword) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionHasPerformanceKeyword,

    -- Aggregated Post Metrics for Questions
    COUNT(DISTINCT cpd_q.PostId) FILTER (WHERE cpd_q.PostTypeId = 1) AS QuestionsCount,
    AVG(cpd_q.Score) FILTER (WHERE cpd_q.PostTypeId = 1) AS AvgQuestionScore,
    MAX(cpd_q.EditCount) FILTER (WHERE cpd_q.PostTypeId = 1) AS MaxQuestionEditCount,
    SUM(cpd_q.FavoriteCount) FILTER (WHERE cpd_q.PostTypeId = 1) AS TotalQuestionFavorites,
    SUM(CASE WHEN cpd_q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) FILTER (WHERE cpd_q.PostTypeId = 1) AS QuestionsWithAcceptedAnswers,
    CAST(SUM(CASE WHEN cpd_q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) FILTER (WHERE cpd_q.PostTypeId = 1) AS DECIMAL) / NULLIF(COUNT(cpd_q.PostId) FILTER (WHERE cpd_q.PostTypeId = 1), 0) AS AcceptedAnswerRateForQuestions,

    -- Aggregated Post Metrics for Answers
    COUNT(DISTINCT cpd_a.PostId) FILTER (WHERE cpd_a.PostTypeId = 2) AS AnswersCount,
    AVG(cpd_a.Score) FILTER (WHERE cpd_a.PostTypeId = 2) AS AvgAnswerScore,
    SUM(CASE WHEN cpd_a.Score >= 10 THEN 1 ELSE 0 END) FILTER (WHERE cpd_a.PostTypeId = 2) AS HighScoringAnswers,
    SUM(CASE WHEN cpd_a.IsCommunityOwned THEN 1 ELSE 0 END) FILTER (WHERE cpd_a.PostTypeId = 2) AS CommunityOwnedAnswers,
    
    -- Tag contribution for this user for specific tags
    MAX(CASE WHEN tum.TagName = 'sql' THEN tum.TaggedPostsCount ELSE 0 END) AS SQLTagPostsCount,
    MAX(CASE WHEN tum.TagName = 'python' THEN tum.AvgScoreForTag ELSE NULL END) AS PythonTagAvgScore,

    -- Ratio of user's reputation to total votes received on their posts
    CAST(u.Reputation AS DECIMAL) / NULLIF(us.TotalPostScore, 0) AS ReputationToPostScoreRatio,

    -- Check if the user has edited any TagWiki posts
    MAX(CASE WHEN ph_tw.PostHistoryTypeId IN (5, 6) AND p_tw.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS HasEditedTagWiki,
    
    -- Correlated subquery example: Get the creation date of the highest-scored post by this user (if any)
    (
        SELECT p_high.CreationDate
        FROM Posts p_high
        WHERE p_high.OwnerUserId = u.Id
        ORDER BY p_high.Score DESC, p_high.CreationDate DESC
        LIMIT 1
    ) AS DateOfHighestScoredPost
FROM
    Users u
JOIN
    UserActivitySummary us ON u.Id = us.UserId
LEFT JOIN
    ConsolidatedPostData cpd_q ON u.Id = cpd_q.OwnerUserId AND cpd_q.PostTypeId = 1
LEFT JOIN
    ConsolidatedPostData cpd_a ON u.Id = cpd_a.OwnerUserId AND cpd_a.PostTypeId = 2
LEFT JOIN
    TagUsageMetrics tum ON tum.TagName IN ('sql', 'python', 'javascript')
LEFT JOIN
    PostHistory ph_tw ON u.Id = ph_tw.UserId
LEFT JOIN
    Posts p_tw ON ph_tw.PostId = p_tw.Id
WHERE
    u.Reputation > 1000 -- Focus on more active users
    AND (us.TotalQuestions > 5 OR us.TotalAnswers > 10) -- Only users who contribute significantly
    AND u.CreationDate >= '2010-01-01' -- Filter newer users
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.Location,
    us.TotalPosts, us.TotalQuestions, us.TotalAnswers, us.TotalPostScore, us.TotalPostViews,
    us.TotalComments, us.TotalBadges, us.LastPostActivity, us.LastCommentActivity,
    us.AvgDaysBetweenPosts, us.UniqueTagsUsed, us.TotalUpVotesGiven, us.TotalDownVotesGiven

UNION ALL

-- Second part of the UNION ALL: Users with high recent activity in terms of edits or comments,
-- or those who contribute to closing/reopening posts
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.Views AS UserProfileViews,
    u.UpVotes AS UserUpVotesReceived,
    u.DownVotes AS UserDownVotesReceived,
    COALESCE(u.Location, 'N/A') AS UserLocation,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.TotalPostScore,
    us.TotalPostViews,
    us.TotalComments,
    us.TotalBadges,
    us.LastPostActivity,
    us.LastCommentActivity,
    us.AvgDaysBetweenPosts,
    us.UniqueTagsUsed,
    us.TotalUpVotesGiven,
    us.TotalDownVotesGiven,
    NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationTier,
    CAST(us.TotalPostScore AS DECIMAL) / NULLIF(us.TotalPosts, 0) AS AvgScorePerPost,
    CAST(us.TotalUpVotesGiven AS DECIMAL) / NULLIF(us.TotalDownVotesGiven + us.TotalUpVotesGiven, 0) AS UpVoteEngagementRatio,

    LAST_VALUE(cpd_q.PostId) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionId,
    LAST_VALUE(cpd_q.TitleLength) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionTitleLength,
    LAST_VALUE(cpd_q.PostEngagementScore) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionEngagementScore,
    LAST_VALUE(cpd_q.EditToCommentRatio) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionEditToCommentRatio,
    LAST_VALUE(cpd_q.HasPerformanceKeyword) OVER (PARTITION BY u.Id ORDER BY cpd_q.PostCreationDate DESC) AS LatestQuestionHasPerformanceKeyword,

    COUNT(DISTINCT cpd_q.PostId) FILTER (WHERE cpd_q.PostTypeId = 1) AS QuestionsCount,
    AVG(cpd_q.Score) FILTER (WHERE cpd_q.PostTypeId = 1) AS AvgQuestionScore,
    MAX(cpd_q.EditCount) FILTER (WHERE cpd_q.PostTypeId = 1) AS MaxQuestionEditCount,
    SUM(cpd_q.FavoriteCount) FILTER (WHERE cpd_q.PostTypeId = 1) AS TotalQuestionFavorites,
    SUM(CASE WHEN cpd_q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) FILTER (WHERE cpd_q.PostTypeId = 1) AS QuestionsWithAcceptedAnswers,
    CAST(SUM(CASE WHEN cpd_q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) FILTER (WHERE cpd_q.PostTypeId = 1) AS DECIMAL) / NULLIF(COUNT(cpd_q.PostId) FILTER (WHERE cpd_q.PostTypeId = 1), 0) AS AcceptedAnswerRateForQuestions,

    COUNT(DISTINCT cpd_a.PostId) FILTER (WHERE cpd_a.PostTypeId = 2) AS AnswersCount,
    AVG(cpd_a.Score) FILTER (WHERE cpd_a.PostTypeId = 2) AS AvgAnswerScore,
    SUM(CASE WHEN cpd_a.Score >= 10 THEN 1 ELSE 0 END) FILTER (WHERE cpd_a.PostTypeId = 2) AS HighScoringAnswers,
    SUM(CASE WHEN cpd_a.IsCommunityOwned THEN 1 ELSE 0 END) FILTER (WHERE cpd_a.PostTypeId = 2) AS CommunityOwnedAnswers,

    MAX(CASE WHEN tum.TagName = 'sql' THEN tum.TaggedPostsCount ELSE 0 END) AS SQLTagPostsCount,
    MAX(CASE WHEN tum.TagName = 'python' THEN tum.AvgScoreForTag ELSE NULL END) AS PythonTagAvgScore,

    CAST(u.Reputation AS DECIMAL) / NULLIF(us.TotalPostScore, 0) AS ReputationToPostScoreRatio,

    MAX(CASE WHEN ph_tw.PostHistoryTypeId IN (5, 6) AND p_tw.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS HasEditedTagWiki,

    (
        SELECT p_high.CreationDate
        FROM Posts p_high
        WHERE p_high.OwnerUserId = u.Id
        ORDER BY p_high.Score DESC, p_high.CreationDate DESC
        LIMIT 1
    ) AS DateOfHighestScoredPost
FROM
    Users u
JOIN
    UserActivitySummary us ON u.Id = us.UserId
LEFT JOIN
    ConsolidatedPostData cpd_q ON u.Id = cpd_q.OwnerUserId AND cpd_q.PostTypeId = 1
LEFT JOIN
    ConsolidatedPostData cpd_a ON u.Id = cpd_a.OwnerUserId AND cpd_a.PostTypeId = 2
LEFT JOIN
    TagUsageMetrics tum ON tum.TagName IN ('sql', 'python', 'javascript')
LEFT JOIN
    PostHistory ph_tw ON u.Id = ph_tw.UserId
LEFT JOIN
    Posts p_tw ON ph_tw.PostId = p_tw.Id
WHERE
    u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 month' -- Recently active
    AND (us.TotalComments > 50 OR EXISTS (SELECT 1 FROM PostHistory ph_close WHERE ph_close.UserId = u.Id AND ph_close.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' AND ph_close.PostHistoryTypeId IN (10, 11))) -- Many comments or recent close/reopen votes
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.Location,
    us.TotalPosts, us.TotalQuestions, us.TotalAnswers, us.TotalPostScore, us.TotalPostViews,
    us.TotalComments, us.TotalBadges, us.LastPostActivity, us.LastCommentActivity,
    us.AvgDaysBetweenPosts, us.UniqueTagsUsed, us.TotalUpVotesGiven, us.TotalDownVotesGiven
ORDER BY
    Reputation DESC, UserProfileViews DESC;
