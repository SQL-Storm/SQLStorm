-- {"query": "48010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 487} 

SELECT
    u.DisplayName AS UserName,
    COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionsAsked,
    COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswersPosted,
    SUM(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
    SUM(CASE WHEN pt.Name = 'Answer' THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN pt.Name = 'Question' THEN DATEDIFF(day, p.CreationDate, GETDATE()) ELSE NULL END) AS AvgDaysSinceQuestion,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditsMade
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    Comments c ON u.Id = c.UserId
WHERE
    u.Id < 1000000 -- Limiting to a subset of users for performance demonstration
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    QuestionsAsked DESC, AnswersPosted DESC, TotalQuestionViews DESC;
