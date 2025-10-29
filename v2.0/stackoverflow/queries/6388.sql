-- {"query": "6388.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 465}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS HistoryDate,
    (
        SELECT 
            STRING_AGG(cl.Name, ', ')
        FROM 
            CloseReasonTypes cl
        WHERE 
            CAST(cl.Id AS VARCHAR) = CAST(ph.Comment AS VARCHAR)
    ) AS CloseReason,
    (
        SELECT 
            COUNT(*)
        FROM 
            Votes v
        WHERE 
            v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    ) AS VoteScore,
    (
        SELECT 
            COUNT(*)
        FROM 
            Comments c
        WHERE 
            c.PostId = p.Id
    ) AS CommentCount
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 1000
    AND p.LastEditDate > p.CreationDate
    AND p.Score > 10
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate,
    p.Score,
    p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, p.Score DESC
LIMIT 100;