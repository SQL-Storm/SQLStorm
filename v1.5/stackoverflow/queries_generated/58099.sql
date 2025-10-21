-- {"query": "58099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1558} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), ', ') AS AllTags,
        COUNT(DISTINCT ph.Id) AS PostEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 10)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    us.*,
    RANK() OVER (ORDER BY us.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY us.TotalPosts DESC) AS ActivityRank,
    (us.UpvotesGiven - us.DownvotesReceived) AS NetVotes,
    (us.GoldBadges * 3 + us.SilverBadges * 2 + us.BronzeBadges) AS BadgeScore
FROM UserStats us
ORDER BY NetVotes DESC, BadgeScore DESC
LIMIT 100;
