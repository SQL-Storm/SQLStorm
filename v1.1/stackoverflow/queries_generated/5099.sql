-- {"query": "5099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1435} 
WITH
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LastGoldBadgeDate,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(p.ViewCount) AS TotalViews,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score::float END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score::float END) AS AvgAnswerScore,
        SUM(p.CommentCount) AS TotalCommentCountOnPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
FavoriteAndAnswerAcceptance AS (
    SELECT
        q.OwnerUserId AS UserId,
        COUNT(DISTINCT f.Id) AS TotalFavorites,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS AcceptedAnswersBySelf,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId AND a.OwnerUserId <> q.OwnerUserId THEN a.Id END) AS AcceptedAnswersByOthers
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Votes f ON f.PostId = q.Id AND f.VoteTypeId = 5
    WHERE q.PostTypeId = 1
    GROUP BY q.OwnerUserId
),
TagDiversity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT TRIM(BOTH '"' FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))) AS DistinctTagsUsed
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(*) AS RecentPostsLast30d,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswersLast30d
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY u.Id
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalBadges,
    ua.LastGoldBadgeDate,
    ua.FirstPostDate,
    ua.LastPostDate,
    ua.TotalViews,
    ua.ReputationRank,
    COALESCE(qas.QuestionsAsked,0) AS QuestionsAsked,
    COALESCE(qas.AnswersGiven,0) AS AnswersGiven,
    COALESCE(qas.QuestionScoreSum,0) AS QuestionScoreSum,
    COALESCE(qas.AnswerScoreSum,0) AS AnswerScoreSum,
    COALESCE(qas.AvgQuestionScore,0) AS AvgQuestionScore,
    COALESCE(qas.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(qas.TotalCommentCountOnPosts,0) AS TotalCommentCountOnPosts,
    COALESCE(faa.TotalFavorites,0) AS TotalFavoritesOnQuestions,
    COALESCE(faa.AcceptedAnswersBySelf,0) AS AcceptedAnswersBySelf,
    COALESCE(faa.AcceptedAnswersByOthers,0) AS AcceptedAnswersByOthers,
    COALESCE(td.DistinctTagsUsed,0) AS DistinctTagsUsed,
    COALESCE(ura.RecentPostsLast30d,0) AS RecentPostsLast30d,
    COALESCE(ura.RecentAnswersLast30d,0) AS RecentAnswersLast30d,
    CASE
        WHEN ua.TotalPosts = 0 THEN NULL
        ELSE ROUND(COALESCE(qas.AnswersGiven,0)::numeric / NULLIF(ua.TotalPosts,0),2)
    END AS AnswerPostRatio,
    CASE
        WHEN ua.TotalBadges = 0 THEN 'None'
        WHEN ua.TotalBadges <= 3 THEN 'Beginner'
        WHEN ua.TotalBadges <= 10 THEN 'Intermediate'
        ELSE 'Expert'
    END AS BadgeLevel,
    CASE
        WHEN ua.TotalViews IS NULL OR ua.TotalViews = 0 THEN 'Unseen'
        WHEN ua.TotalViews < 1000 THEN 'Rising'
        ELSE 'Popular'
    END AS PopularityCategory,
    CASE
        WHEN ua.LastGoldBadgeDate IS NULL THEN 'Never'
        WHEN ua.LastGoldBadgeDate > NOW() - INTERVAL '1 year' THEN 'Last year'
        ELSE 'More than 1 year ago'
    END AS GoldBadgeRecency,
    (SELECT COUNT(DISTINCT c2.Id) FROM Comments c2 WHERE c2.UserId = ua.UserId AND c2.Score > 5) AS HighlyUpvotedComments
FROM UserActivity ua
LEFT JOIN QuestionAnswerStats qas ON ua.UserId = qas.UserId
LEFT JOIN FavoriteAndAnswerAcceptance faa ON ua.UserId = faa.UserId
LEFT JOIN TagDiversity td ON ua.UserId = td.UserId
LEFT JOIN UserRecentActivity ura ON ua.UserId = ura.UserId
WHERE ua.TotalPosts > 0
  AND (ua.Reputation > 500 OR COALESCE(faa.TotalFavorites,0) > 10)
  AND (ua.FirstPostDate IS NULL OR ua.FirstPostDate < NOW() - INTERVAL '90 days')
ORDER BY
    ua.ReputationRank,
    ua.TotalPosts DESC,
    COALESCE(qas.AnswersGiven,0) DESC
LIMIT 100;