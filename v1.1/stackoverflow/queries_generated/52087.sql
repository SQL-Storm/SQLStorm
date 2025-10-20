-- {"query": "52087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 686} 
WITH UserPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(*) AS TotalPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserComments AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVotesReceived AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserScores AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(up.TotalPosts, 0) AS TotalPosts,
        COALESCE(uc.CommentCount, 0) AS TotalComments,
        COALESCE(uvr.NetVotesReceived, 0) AS NetVotes,
        COALESCE(ub.TotalBadges, 0) AS TotalBadges,
        (COALESCE(up.TotalPosts, 0) * 2) + COALESCE(uc.CommentCount, 0) + COALESCE(uvr.NetVotesReceived, 0) + COALESCE(ub.TotalBadges, 0) AS EngagementScore
    FROM Users u
    LEFT JOIN UserPosts up ON u.Id = up.OwnerUserId
    LEFT JOIN UserComments uc ON u.Id = uc.UserId
    LEFT JOIN UserVotesReceived uvr ON u.Id = uvr.OwnerUserId
    LEFT JOIN UserBadges ub ON u.Id = ub.UserId
    WHERE u.Reputation > 100
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY EngagementScore DESC) AS Rank
    FROM UserScores
)
SELECT 
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.TotalComments,
    ru.NetVotes,
    ru.TotalBadges,
    ru.EngagementScore,
    ru.Rank
FROM RankedUsers ru
WHERE ru.Rank <= 100
ORDER BY ru.Rank;