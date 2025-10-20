-- {"query": "52047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 1005} 
WITH user_post_stats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.AnswerCount) AS TotalAnswersReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
),
user_vote_stats AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountiesStarted,
        SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Votes v
    GROUP BY v.UserId
),
user_badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes
    FROM Badges b
    GROUP BY b.UserId
),
user_comment_stats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
user_link_stats AS (
    SELECT 
        pl.PostId,
        COUNT(pl.Id) AS LinksCreated
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY pl.PostId
)
SELECT 
    ups.UserId,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ROUND(ups.AvgPostScore, 2) AS AvgPostScore,
    ups.TotalViews,
    ups.TotalAnswersReceived,
    COALESCE(uvs.TotalVotes, 0) AS TotalVotes,
    COALESCE(uvs.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(uvs.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(uvs.BountiesStarted, 0) AS BountiesStarted,
    COALESCE(uvs.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.UniqueBadgeTypes, 0) AS UniqueBadgeTypes,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    ROUND(COALESCE(ucs.AvgCommentScore, 0), 2) AS AvgCommentScore,
    COALESCE(SUM(uls.LinksCreated), 0) AS TotalLinksCreated
FROM user_post_stats ups
LEFT JOIN user_vote_stats uvs ON ups.UserId = uvs.UserId
LEFT JOIN user_badge_stats ubs ON ups.UserId = ubs.UserId
LEFT JOIN user_comment_stats ucs ON ups.UserId = ucs.UserId
LEFT JOIN user_link_stats uls ON ups.UserId = uls.PostId
WHERE ups.TotalPosts > 0
GROUP BY ups.UserId, ups.Reputation, ups.TotalPosts, ups.Questions, ups.Answers, ups.AvgPostScore, ups.TotalViews, ups.TotalAnswersReceived,
         uvs.TotalVotes, uvs.UpvotesGiven, uvs.DownvotesGiven, uvs.BountiesStarted, uvs.TotalBountyAmount,
         ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.UniqueBadgeTypes,
         ucs.TotalComments, ucs.AvgCommentScore
ORDER BY ups.Reputation DESC, ups.TotalPosts DESC
LIMIT 100;