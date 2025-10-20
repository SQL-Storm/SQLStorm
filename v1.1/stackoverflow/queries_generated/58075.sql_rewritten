-- {"query": "58075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1238} 
WITH UserContributions AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        COUNT(DISTINCT ph.Id) AS PostEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS PostClosures
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate >= '2022-01-01'
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
      AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, p.Score
)
SELECT 
    uc.UserId,
    uc.DisplayName,
    uc.Reputation,
    uc.TotalPosts,
    uc.QuestionsAsked,
    uc.AnswersProvided,
    uc.TotalComments,
    uc.UpvotesReceived,
    uc.DownvotesReceived,
    uc.TotalBadges,
    uc.GoldBadges,
    ROUND(uc.AvgPostScore, 2) AS AvgPostScore,
    uc.PostEdits,
    uc.PostClosures,
    RANK() OVER (ORDER BY uc.TotalPosts DESC, uc.UpvotesReceived DESC) AS ContributionRank,
    DENSE_RANK() OVER (PARTITION BY CASE 
        WHEN uc.Reputation >= 100000 THEN 'Legendary' 
        WHEN uc.Reputation >= 50000 THEN 'Epic' 
        WHEN uc.Reputation >= 25000 THEN 'Veteran' 
        ELSE 'Member' END 
        ORDER BY uc.TotalBadges DESC) AS BadgeClassRank
FROM UserContributions uc
WHERE uc.Reputation > 10000
  AND (uc.QuestionsAsked > 50 OR uc.AnswersProvided > 100)
  AND uc.TotalBadges >= 5
ORDER BY ContributionRank ASC, BadgeClassRank ASC
LIMIT 100;