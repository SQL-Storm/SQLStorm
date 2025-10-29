-- {"query": "5330.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 404} 
SELECT
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounty,
    COUNT(DISTINCT cl.Id) AS ClosedCount,
    MAX(p.LastActivityDate) AS LastActivity
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN
    PostHistory ph2 ON ph2.PostId = p.Id
LEFT JOIN
    CloseReasonTypes cl ON CAST(ph.Comment AS VARCHAR(100)) LIKE CONCAT('%', cl.Name, '%')
WHERE
    -- Only consider users with at least one post in the last 365 days
    u.Reputation > 0
    AND (p.CreationDate IS NULL OR p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days')
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    LastActivity DESC, TotalPosts DESC
LIMIT 100;