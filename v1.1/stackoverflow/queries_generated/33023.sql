-- {"query": "33023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 360} 
SELECT
    u.Id AS UserID,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT t.Id) AS TagCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Tags t ON t.Id IN (
    SELECT unnest(string_to_array(substring(tg.Tags, 2, length(tg.Tags)-2), '><')) FROM Posts tg WHERE tg.OwnerUserId = u.Id AND tg.PostTypeId = 1
)
LEFT JOIN PostLinks pl ON pl.PostId IN (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id
)
GROUP BY u.Id, u.DisplayName;