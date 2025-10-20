-- {"query": "59091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 575} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN p.Id END) as OwnedAnswers,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT v.Id) as Votes,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagInterests,
    MAX(p.CreationDate) as LastPostDate,
    AVG(p.Score) as AvgPostScore,
    SUM(p.ViewCount) as TotalViews,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
LEFT JOIN Comments c ON u.Id = c.UserId OR u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN (
    SELECT DISTINCT p.Id, t.TagName 
    FROM Posts p 
    JOIN Posts p2 ON p.Id = p2.ParentId 
    JOIN (
        SELECT Id, UNNEST(STRING_TO_ARRAY(Tags, '>')) as TagName 
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON p2.Id = t.Id
) t ON p.Id = t.Id
WHERE u.CreationDate >= '2010-01-01' 
    AND u.Reputation > 100
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2 OR p.PostTypeId IS NULL)
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) >= 10
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000;