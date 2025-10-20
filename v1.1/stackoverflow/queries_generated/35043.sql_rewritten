-- {"query": "35043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 973} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 10000
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
      AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) >= 100
    ORDER BY u.Reputation DESC
    LIMIT 20
), UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgScore,
        SUM(p.CommentCount) AS TotalComments,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
      AND p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId, p.PostTypeId
), UserVoteStats AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        COUNT(v.Id) AS TotalVotesReceived
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
      AND p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId
), UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    GROUP BY b.UserId
)
SELECT 
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    COALESCE(SUM(ups.TotalQuestions), 0) AS QuestionsPosted,
    COALESCE(SUM(ups.TotalAnswers), 0) AS AnswersPosted,
    ROUND(COALESCE(AVG(ups.AvgScore), 0),2) AS AvgPostScore,
    COALESCE(SUM(ups.TotalComments), 0) AS CommentsOnPosts,
    COALESCE(SUM(ups.TotalViews), 0) AS ViewsOnPosts,
    COALESCE(uvs.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(uvs.DownvotesReceived, 0) AS DownvotesReceived,
    COALESCE(uvs.TotalVotesReceived, 0) AS TotalVotesReceived,
    COALESCE(ubs.TotalBadges, 0) AS BadgesEarned,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    MIN(u.CreationDate) AS UserJoined,
    MAX(p.CreationDate) AS LastActivity
FROM TopUsers tu
LEFT JOIN UserPostStats ups ON ups.OwnerUserId = tu.Id
LEFT JOIN UserVoteStats uvs ON uvs.OwnerUserId = tu.Id
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tu.Id
LEFT JOIN Users u ON u.Id = tu.Id
LEFT JOIN Posts p ON p.OwnerUserId = tu.Id
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation, tu.PostCount,
    uvs.UpvotesReceived, uvs.DownvotesReceived, uvs.TotalVotesReceived,
    ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
    u.CreationDate
ORDER BY tu.Reputation DESC, tu.PostCount DESC
LIMIT 20;