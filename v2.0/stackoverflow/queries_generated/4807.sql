-- {"query": "4807.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1204} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestionCount,
        AVG(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS AvgAnswersPerQuestion,
        MAX(COALESCE(b.Date, '1900-01-01')) AS LastBadgeDate,
        (
            SELECT COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END)
            FROM Votes v
            WHERE v.UserId = u.Id
        ) AS TotalUpvotesCast,
        (
            SELECT COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END)
            FROM Votes v
            WHERE v.UserId = u.Id
        ) AS TotalDownvotesCast
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.QuestionCount,
    ua.PositiveScoreQuestionCount,
    ua.AvgAnswersPerQuestion,
    rp.Title AS LatestQuestionTitle,
    rp.Tags AS LatestQuestionTags,
    rp.Score AS LatestQuestionScore,
    rp.FavoriteCount AS LatestQuestionFavoriteCount,
    ca.CommentCountOnPost,
    ca.PositiveScoreComments,
    ca.AvgCommentScore,
    ua.TotalUpvotesCast,
    ua.TotalDownvotesCast,
    CASE
        WHEN STRFTIME('%Y', ua.UserCreationDate) < STRFTIME('%Y', DATE('now', '-1 year')) THEN 'Established'
        ELSE 'Newer'
    END AS UserAgeCategory,
    CASE
        WHEN ua.Reputation > 100000 THEN 'High'
        WHEN ua.Reputation > 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationTier,
    CASE
        WHEN ca.LatestCommentDate > DATE('now', '-7 days') THEN 'Recent Activity'
        ELSE 'Dormant'
    END AS RecentCommentActivity,
    COUNT(DISTINCT p.Id) AS TotalPostsOwned,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
    SUM(p.ViewCount) AS TotalViewsOnPosts,
    SUM(p.CommentCount) AS TotalCommentsOnPosts,
    AVG(p.Score) AS AveragePostScore,
    MAX(p.LastActivityDate) AS UserLastActivityDate,
    (SELECT COUNT(*) FROM Badges WHERE UserId = ua.UserId AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = ua.UserId AND Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = ua.UserId AND Class = 3) AS BronzeBadges,
    CASE
        WHEN ua.LastBadgeDate IS NULL OR ua.LastBadgeDate < DATE('now', '-365 days') THEN 'No Recent Badges'
        ELSE 'Has Recent Badges'
    END AS BadgeStatus
FROM UserActivity ua
LEFT JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.FavoriteCount,
    ca.CommentCountOnPost,
    ca.PositiveScoreComments,
    ca.AvgCommentScore,
    ua.TotalUpvotesCast,
    ua.TotalDownvotesCast,
    ua.LastBadgeDate
HAVING COUNT(DISTINCT p.Id) > 5 -- Only include users with more than 5 posts
ORDER BY ua.Reputation DESC, ua.QuestionCount DESC;