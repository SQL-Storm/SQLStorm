-- {"query": "33082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 408} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswersCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL) AS QuestionsClosed,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN
    Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN
    Votes v ON u.Id = v.UserId
LEFT JOIN
    Comments c ON u.Id = c.UserId
LEFT JOIN
    Badges b ON u.Id = b.UserId
WHERE
    u.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    QuestionsCount DESC
LIMIT 100;