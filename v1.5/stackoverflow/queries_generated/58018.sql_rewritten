-- {"query": "58018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1327} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsAsked,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswersProvided,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 2) AS UpvotesReceived,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 3) AS DownvotesReceived,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    (SELECT STRING_AGG(DISTINCT ph.Text, '; ') FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND ph.PostHistoryTypeId = 5) AS RecentEdits,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND pl.LinkTypeId = 3) AS DuplicatePosts
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Score
HAVING 
    COUNT(p.Id) > 10
ORDER BY 
    ReputationRank, AvgPostScore DESC, QuestionsAsked DESC
LIMIT 
    100;