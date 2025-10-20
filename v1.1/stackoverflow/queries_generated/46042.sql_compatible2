WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><') AS tag_array,
        COUNT(*) AS tag_post_count,
        AVG(p.Score) AS avg_tag_score,
        SUM(p.ViewCount) AS total_tag_views
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.Tags
),
TopAnswerers AS (
    SELECT 
        a.OwnerUserId,
        q.OwnerUserId AS QuestionOwnerId,
        COUNT(*) AS AnswersGiven,
        COUNT(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 END) AS AcceptedAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0) AS AvgResponseTimeHours
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND q.PostTypeId = 1
        AND a.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '18 months'
    GROUP BY a.OwnerUserId, q.OwnerUserId
    HAVING COUNT(*) > 3
),
VotingPatterns AS (
    SELECT 
        v.UserId,
        v.PostId,
        p.OwnerUserId AS PostOwnerId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY v.UserId, v.PostId, p.OwnerUserId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
        AND c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY c.UserId, c.PostId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(uem.AvgPostScore, 2) AS AvgPostScore,
    uem.TotalQuestionViews,
    uem.GoldBadges,
    uem.SilverBadges,
    uem.BronzeBadges,
    COALESCE(ta_summary.total_answers, 0) AS TotalAnswersGiven,
    COALESCE(ta_summary.total_accepted, 0) AS TotalAcceptedAnswers,
    ROUND(COALESCE(ta_summary.acceptance_rate, 0), 2) AS AcceptanceRate,
    ROUND(COALESCE(ta_summary.avg_response_hours, 0), 2) AS AvgResponseTimeHours,
    COALESCE(vp_summary.total_upvotes_cast, 0) AS UpvotesCast,
    COALESCE(vp_summary.total_downvotes_cast, 0) AS DownvotesCast,
    COALESCE(vp_summary.total_favorites_cast, 0) AS FavoritesCast,
    COALESCE(ca_summary.total_comments, 0) AS TotalComments,
    ROUND(COALESCE(ca_summary.avg_comment_score, 0), 2) AS AvgCommentScore,
    EXTRACT(DAY FROM (CAST('2024-10-01' AS date) - uem.UserCreationDate)) AS DaysSinceJoined,
    ROUND(uem.TotalPosts / NULLIF(EXTRACT(DAY FROM (CAST('2024-10-01' AS date) - uem.UserCreationDate)), 0), 3) AS PostsPerDay,
    DENSE_RANK() OVER (ORDER BY uem.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY uem.TotalPosts DESC) AS PostCountRank,
    DENSE_RANK() OVER (ORDER BY COALESCE(ta_summary.acceptance_rate, 0) DESC) AS AcceptanceRateRank,
    uem.UserId,
    uem.UserCreationDate
FROM UserEngagementMetrics uem
LEFT JOIN (
    SELECT 
        OwnerUserId,
        SUM(AnswersGiven) AS total_answers,
        SUM(AcceptedAnswers) AS total_accepted,
        AVG(CASE WHEN AnswersGiven > 0 THEN CAST(AcceptedAnswers AS DECIMAL) / AnswersGiven * 100 ELSE 0 END) AS acceptance_rate,
        AVG(AvgResponseTimeHours) AS avg_response_hours
    FROM TopAnswerers
    GROUP BY OwnerUserId
) ta_summary ON uem.UserId = ta_summary.OwnerUserId
LEFT JOIN (
    SELECT 
        UserId,
        SUM(Upvotes) AS total_upvotes_cast,
        SUM(Downvotes) AS total_downvotes_cast,
        SUM(Favorites) AS total_favorites_cast
    FROM VotingPatterns
    GROUP BY UserId
) vp_summary ON uem.UserId = vp_summary.UserId
LEFT JOIN (
    SELECT 
        UserId,
        SUM(CommentCount) AS total_comments,
        AVG(AvgCommentScore) AS avg_comment_score
    FROM CommentActivity
    GROUP BY UserId
) ca_summary ON uem.UserId = ca_summary.UserId
WHERE uem.TotalPosts >= 10
ORDER BY 
    uem.Reputation DESC,
    COALESCE(ta_summary.acceptance_rate, 0) DESC,
    uem.TotalPosts DESC
LIMIT 500;