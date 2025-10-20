-- {"query": "33043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 535} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT bv.Id) FILTER (WHERE bv.Name LIKE '%Gold%') AS GoldBadges,
    COUNT(DISTINCT bv.Id) FILTER (WHERE bv.Name LIKE '%Silver%') AS SilverBadges,
    COUNT(DISTINCT bv.Id) FILTER (WHERE bv.Name LIKE '%Bronze%') AS BronzeBadges,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT v2.Id) FILTER (WHERE v2.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v3.Id) FILTER (WHERE v3.VoteTypeId = 3) AS DownVotes,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    COUNT(DISTINCT pl2.Id) AS DuplicateLinks,
    COUNT(DISTINCT t.Id) AS TotalTags,
    COUNT(DISTINCT wh.Id) AS TotalPostHistory,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate,
    MAX(c.CreationDate) AS LastCommentDate
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges bv ON bv.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Votes v2 ON v2.UserId = u.Id AND v2.VoteTypeId = 2
LEFT JOIN Votes v3 ON v3.UserId = u.Id AND v3.VoteTypeId = 3
LEFT JOIN PostLinks pl ON pl.PostId IN (p.Id, a.Id) AND pl.RelatedPostId IS NOT NULL
LEFT JOIN PostLinks pl2 ON pl2.PostId IN (p.Id, a.Id) AND pl2.LinkTypeId = 3
LEFT JOIN Tags t ON t.ExcerptPostId IN (p.Id, a.Id)
LEFT JOIN PostHistory wh ON wh.UserId = u.Id
GROUP BY u.Id, u.DisplayName
ORDER BY TotalQuestions DESC, TotalAnswers DESC
LIMIT 100;