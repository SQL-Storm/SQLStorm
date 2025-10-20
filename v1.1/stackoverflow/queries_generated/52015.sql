-- {"query": "52015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 285} 
SELECT u.Id, u.DisplayName, u.Reputation,
       COUNT(DISTINCT p.Id) AS QuestionCount,
       COUNT(DISTINCT a.Id) AS AnswerCount,
       SUM(p.Score) AS TotalQuestionScore,
       SUM(a.Score) AS TotalAnswerScore,
       AVG(p.ViewCount) AS AvgQuestionViews,
       COUNT(DISTINCT b.Id) AS BadgeCount,
       COUNT(DISTINCT v.Id) AS VoteReceivedCount,
       COUNT(DISTINCT c.Id) AS CommentReceivedCount,
       RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON v.PostId = p.Id OR v.PostId = a.Id
LEFT JOIN Comments c ON c.PostId = p.Id OR c.PostId = a.Id
WHERE u.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING SUM(p.Score) > 1000 OR SUM(a.Score) > 1000
ORDER BY u.Reputation DESC
LIMIT 100;