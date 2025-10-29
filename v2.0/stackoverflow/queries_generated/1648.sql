-- {"query": "1648.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2663} 

WITH UserActivitySummary AS (
    -- Aggregates basic user activity metrics like total posts, answers, comments, and votes.
    -- Also calculates the latest user activity timestamp across all interactions.
    SELECT
        u.Id AS UserId,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p_q.Id) AS TotalQuestionsOwned,
        COUNT(DISTINCT p_a.Id) AS TotalAnswersGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        MAX(COALESCE(p_q.LastActivityDate, p_a.LastActivityDate, c.CreationDate, v.CreationDate, u.LastAccessDate)) AS LatestUserActivity
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostAggregates AS (
    -- Calculates various aggregate metrics for each post, including associated tags, edit history,
    -- comment counts, and vote counts (UpMod, DownMod, Favorite).
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.ClosedDate,
        p.ParentId,
        STRING_AGG(DISTINCT t_unnest.TagName, ',') FILTER (WHERE t_unnest.TagName IS NOT NULL) AS AssociatedTags,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Title'),
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Body'),
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Tags')
        ) THEN ph.CreationDate ELSE NULL END) AS LastEditDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') THEN 'Closed'
                 WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened') THEN 'Reopened'
                 ELSE NULL END) AS LatestStatusChange,
        COUNT(DISTINCT cmt.Id) AS CommentCountOnPost,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesOnPost,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesOnPost,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoritesOnPost
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments cmt ON p.Id = cmt.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
        WHERE p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
    ) AS t_unnest ON TRUE
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.FavoriteCount, p.CreationDate, p.ClosedDate, p.ParentId
),
UserReputationRank AS (
    -- Ranks users by reputation and provides aggregated post scores and views.
    -- Includes a non-correlated subquery for the average question score benchmark.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Location,
        u.AboutMe,
        u.Views AS UserProfileViews,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS GlobalReputationRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) AS ReputationPercentile,
        AVG(pa.PostScore) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')) AS AvgQuestionScore,
        AVG(pa.PostScore) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')) AS AvgAnswerScore,
        SUM(pa.ViewCount) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')) AS TotalQuestionViews,
        SUM(pa.FavoriteCount) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')) AS TotalQuestionFavorites,
        COUNT(DISTINCT pa.PostId) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') AND pa.ClosedDate IS NOT NULL) AS QuestionsClosedCount,
        COUNT(DISTINCT pa.PostId) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') AND pa.PostScore > (SELECT AVG(PostScore) FROM PostAggregates WHERE PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question'))) AS HighScoreQuestions,
        MAX(pa.PostCreationDate) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')) AS LastQuestionDate,
        MAX(pa.PostCreationDate) FILTER (WHERE pa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')) AS LastAnswerDate
    FROM Users u
    LEFT JOIN PostAggregates pa ON u.Id = pa.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location, u.AboutMe, u.Views
),
BadgeContributionSummary AS (
    -- Summarizes badge counts by class for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
)
-- Main query: Focuses on highly engaged and impactful contributors, combining various user and post metrics.
SELECT
    urr.UserId,
    urr.DisplayName,
    urr.Reputation,
    urr.GlobalReputationRank,
    urr.ReputationPercentile,
    uas.UserCreationDate,
    uas.LastAccessDate,
    EXTRACT(DAY FROM (NOW() - uas.LastAccessDate)) AS DaysSinceLastActive,
    COALESCE(urr.Location, 'Unknown') AS UserLocation,
    COALESCE(
        CASE
            WHEN LENGTH(TRIM(urr.AboutMe)) > 200 THEN SUBSTRING(urr.AboutMe, 1, 197) || '...'
            WHEN LENGTH(TRIM(urr.AboutMe)) > 0 THEN urr.AboutMe
            ELSE NULL
        END, 'No "About Me" description provided.'
    ) AS AboutMeExcerpt,
    uas.TotalQuestionsOwned,
    uas.TotalAnswersGiven,
    uas.TotalCommentsMade,
    uas.TotalVotesCast,
    bcs.TotalBadges,
    bcs.GoldBadges,
    bcs.SilverBadges,
    bcs.BronzeBadges,
    urr.AvgQuestionScore,
    urr.AvgAnswerScore,
    urr.TotalQuestionViews,
    urr.TotalQuestionFavorites,
    CAST(uas.UserUpVotes AS NUMERIC) / NULLIF(uas.UserUpVotes + uas.UserDownVotes, 0) AS OverallUpvoteRatio,
    urr.QuestionsClosedCount,
    urr.HighScoreQuestions,
    CASE
        WHEN urr.Reputation >= 20000 AND bcs.GoldBadges >= 5 AND uas.TotalAnswersGiven > 200 THEN 'Legendary Contributor'
        WHEN urr.Reputation >= 5000 AND urr.AvgAnswerScore IS NOT NULL AND urr.AvgAnswerScore > 10 THEN 'Expert Answerer'
        WHEN uas.TotalQuestionsOwned > 50 AND urr.TotalQuestionViews > 10000 THEN 'Proactive Questioner'
        WHEN uas.LatestUserActivity >= NOW() - INTERVAL '30 days' AND uas.TotalPosts > 0 THEN 'Recently Active'
        ELSE 'Passive Member'
    END AS UserEngagementTier,
    -- Correlated subquery: Checks if user owns any question linked as a duplicate with more than 5 answers.
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        JOIN Posts p_linked ON pl.PostId = p_linked.Id
        WHERE p_linked.OwnerUserId = urr.UserId
          AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
          AND p_linked.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
          AND (SELECT COUNT(ans.Id) FROM Posts ans WHERE ans.ParentId = p_linked.Id AND ans.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')) > 5
    ) AS HasComplexDuplicateQuestion,
    -- Non-correlated subquery: Global average score of answers with at least 5 comments.
    (
        SELECT AVG(PostScore)
        FROM PostAggregates
        WHERE PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
          AND CommentCountOnPost >= 5
    ) AS GlobalAverageAnswerScoreMetric,
    -- Window function: Ranks users within their engagement tier by their total upvotes received across all their posts.
    RANK() OVER (PARTITION BY (CASE
                                    WHEN urr.Reputation >= 20000 AND bcs.GoldBadges >= 5 AND uas.TotalAnswersGiven > 200 THEN 'Legendary Contributor'
                                    WHEN urr.Reputation >= 5000 AND urr.AvgAnswerScore IS NOT NULL AND urr.AvgAnswerScore > 10 THEN 'Expert Answerer'
                                    WHEN uas.TotalQuestionsOwned > 50 AND urr.TotalQuestionViews > 10000 THEN 'Proactive Questioner'
                                    WHEN uas.LatestUserActivity >= NOW() - INTERVAL '30 days' AND uas.TotalPosts > 0 THEN 'Recently Active'
                                    ELSE 'Passive Member'
                                END) ORDER BY uas.UserUpVotes DESC NULLS LAST) AS RankInEngagementTierBySpecificMetric
FROM UserReputationRank urr
LEFT JOIN UserActivitySummary uas ON urr.UserId = uas.UserId
LEFT JOIN BadgeContributionSummary bcs ON urr.UserId = bcs.UserId
WHERE urr.Reputation >= 100
  AND uas.LatestUserActivity >= NOW() - INTERVAL '