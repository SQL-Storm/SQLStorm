-- {"query": "52083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 628} 
WITH UserMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScoreSum,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT *,
        (Reputation * 0.5 + TotalPosts * 0.1 + QuestionScoreSum * 0.2 + AnswerScoreSum * 0.2 + TotalBadges * 10 + GoldBadges * 50 + SilverBadges * 20 + BronzeBadges * 10) AS CompositeScore
    FROM UserMetrics
    WHERE TotalPosts > 0
)
SELECT tu.*,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    STRING_AGG(DISTINCT p.Tags, ', ') AS PostTags
FROM TopUsers tu
LEFT JOIN Badges b ON tu.UserId = b.UserId
LEFT JOIN Posts p ON tu.UserId = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY tu.UserId, tu.Reputation, tu.UserCreationDate, tu.TotalPosts, tu.QuestionScoreSum, tu.AnswerScoreSum, tu.AvgPostScore, tu.TotalComments, tu.TotalVotes, tu.UpVotesReceived, tu.DownVotesReceived, tu.TotalBadges, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges, tu.LastPostHistoryDate, tu.CompositeScore
ORDER BY tu.CompositeScore DESC
LIMIT 100;