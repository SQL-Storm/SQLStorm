-- {"query": "59081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 832} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT c.Id) AS Comments,
    COUNT(DISTINCT b.Id) AS Badges,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    COUNT(DISTINCT v.Id) AS Votes,
    AVG(p.Score) AS AverageScore,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) AS PositiveQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS PositiveAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) AS HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ViewCount > 1000 THEN p.Id END) AS HighViewAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) AS AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId IN (1, 2) AND p.Tags IS NOT NULL THEN p.Id END) AS TaggedPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT u.Id), 0) AS QuestionsPerUser,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT u.Id), 0) AS AnswersPerUser,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01' THEN p.Id END) AS Questions2023,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= '2023-01-01' THEN p.Id END) AS Answers2023,
    COUNT(DISTINCT CASE WHEN b.Date >= '2023-01-01' THEN b.Id END) AS Badges2023
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Id IS NOT NULL 
    AND u.Reputation > 0 
    AND u.CreationDate >= '2020-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0 
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;