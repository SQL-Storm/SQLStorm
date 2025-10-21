-- {"query": "58080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1199} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsAsked,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswersProvided,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v 
         JOIN Posts p ON v.PostId = p.Id 
         WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2) AS UpvotesReceived,
        (SELECT COUNT(*) FROM Votes v 
         JOIN Posts p ON v.PostId = p.Id 
         WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 3) AS DownvotesReceived,
        (SELECT COUNT(*) FROM PostHistory ph 
         WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 5) AS BodyEditsMade,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p 
         JOIN Posts linked ON p.ParentId = linked.Id 
         WHERE p.PostTypeId = 2 AND linked.Tags LIKE '%<sql>%' AND p.OwnerUserId = u.Id) AS SQLAnswers
    FROM Users u
    WHERE u.Reputation > 1000
)
SELECT 
    us.UserId,
    us.Reputation,
    us.GoldBadges,
    us.QuestionsAsked,
    us.AnswersProvided,
    us.TotalComments,
    us.UpvotesReceived,
    us.DownvotesReceived,
    us.BodyEditsMade,
    us.SQLAnswers,
    (us.Reputation * 0.3 + us.GoldBadges * 100 + us.UpvotesReceived * 2 - us.DownvotesReceived * 5) AS ActivityScore
FROM UserStats us
ORDER BY ActivityScore DESC
LIMIT 50;