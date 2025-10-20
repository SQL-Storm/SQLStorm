-- {"query": "52035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 831} 
WITH UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT 
        v.UserId,
        COUNT(*) AS TotalVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetUpVotes
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BadgePoints
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityScore AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.Questions, 0) AS Questions,
        COALESCE(ups.Answers, 0) AS Answers,
        COALESCE(ups.AvgScore, 0) AS AvgPostScore,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
        COALESCE(uvs.TotalVotesGiven, 0) AS TotalVotesGiven,
        COALESCE(uvs.NetUpVotes, 0) AS NetUpVotes,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.BadgePoints, 0) AS BadgePoints,
        (u.Reputation * 0.5 + 
         COALESCE(ups.TotalPosts, 0) * 1.0 + 
         COALESCE(ucs.TotalComments, 0) * 0.5 + 
         COALESCE(uvs.TotalVotesGiven, 0) * 0.2 + 
         COALESCE(ubs.BadgePoints, 0) * 2.0) AS ActivityScore
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY ActivityScore DESC, Reputation DESC) AS Rank
    FROM UserActivityScore
)
SELECT 
    ru.Id,
    ru.Reputation,
    ru.TotalPosts,
    ru.Questions,
    ru.Answers,
    ROUND(ru.AvgPostScore, 2) AS AvgPostScore,
    ru.TotalComments,
    ROUND(ru.AvgCommentScore, 2) AS AvgCommentScore,
    ru.TotalVotesGiven,
    ru.NetUpVotes,
    ru.TotalBadges,
    ru.BadgePoints,
    ROUND(ru.ActivityScore, 2) AS ActivityScore,
    ru.Rank
FROM RankedUsers ru
WHERE ru.Rank <= 1000
ORDER BY ru.Rank;