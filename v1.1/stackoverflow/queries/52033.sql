-- {"query": "52033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 720} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Location,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Location, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        SUM(v.BountyAmount) AS TotalBountySpent
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
TopUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Location,
        ups.Reputation,
        ups.TotalPosts,
        ups.TotalScore,
        ups.AvgScore,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.LatestPostDate,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.BadgeNames,
        uvs.UpVotesGiven,
        uvs.DownVotesGiven,
        uvs.TotalBountySpent,
        ucs.TotalComments,
        ucs.AvgCommentScore,
        ucs.LatestCommentDate
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
    LEFT JOIN UserVoteStats uvs ON ups.UserId = uvs.UserId
    LEFT JOIN UserCommentStats ucs ON ups.UserId = ucs.UserId
    WHERE ups.TotalPosts > 0
    ORDER BY ups.Reputation DESC
    LIMIT 100
)
SELECT 
    tu.*,
    RANK() OVER (ORDER BY tu.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY tu.TotalScore DESC) AS ScoreRank,
    RANK() OVER (ORDER BY tu.TotalBadges DESC) AS BadgeRank
FROM TopUsers tu
ORDER BY ReputationRank;