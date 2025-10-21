SELECT 
    u.Id, 
    u.Reputation, 
    u.DisplayName, 
    COUNT(p.Id) AS PostCount, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedQuestions, 
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedQuestions
FROM 
    Users AS u
LEFT JOIN 
    Posts AS p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes AS v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory AS ph ON p.Id = ph.PostId
GROUP BY 
    u.Id, 
    u.Reputation, 
    u.DisplayName
ORDER BY 
    PostCount DESC;