-- {"query": "59073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 474} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT b.Id) AS Badges,
    COUNT(DISTINCT c.Id) AS Comments,
    COUNT(DISTINCT v.Id) AS Votes,
    COUNT(DISTINCT ph.Id) AS PostHistoryActions,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagsUsed,
    MAX(p.CreationDate) AS LastPostDate,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.FavoriteCount) AS TotalFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) AS AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN (
    SELECT DISTINCT p.Id, t.TagName
    FROM Posts p
    JOIN (
        SELECT Id, UNNEST(STRING_TO_ARRAY(Tags, '>')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON p.Id = t.Id
) t ON p.Id = t.Id
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000;