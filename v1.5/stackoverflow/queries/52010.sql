-- {"query": "52010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 880} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserCommentStats AS (
    SELECT 
        UserId,
        COUNT(*) AS CommentCount,
        SUM(Score) AS TotalCommentScore
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountiesStarted,
        SUM(BountyAmount) AS TotalBountyAmount
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserPostHistoryStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT PostId) AS DistinctPostsEdited
    FROM PostHistory
    WHERE UserId IS NOT NULL AND PostHistoryTypeId IN (4, 5, 6)
    GROUP BY UserId
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalScore,
    ups.TotalViews,
    ups.AvgScore,
    COALESCE(ucs.CommentCount, 0) AS CommentCount,
    COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(uvs.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(uvs.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(uvs.BountiesStarted, 0) AS BountiesStarted,
    COALESCE(uvs.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uphs.TotalEdits, 0) AS TotalEdits,
    COALESCE(uphs.DistinctPostsEdited, 0) AS DistinctPostsEdited,
    -- Complex ranking formula
    (ups.TotalScore * 10 + COALESCE(ucs.CommentCount, 0) * 2 + COALESCE(uvs.UpVotesGiven, 0) * 5 + COALESCE(ubs.TotalBadges, 0) * 50 + COALESCE(uvs.TotalBountyAmount, 0) / 100 + ups.Reputation) AS ImpactScore
FROM UserPostStats ups
LEFT JOIN UserCommentStats ucs ON ups.UserId = ucs.UserId
LEFT JOIN UserVoteStats uvs ON ups.UserId = uvs.UserId
LEFT JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
LEFT JOIN UserPostHistoryStats uphs ON ups.UserId = uphs.UserId
ORDER BY ImpactScore DESC, ups.TotalScore DESC, ups.Reputation DESC
LIMIT 100;