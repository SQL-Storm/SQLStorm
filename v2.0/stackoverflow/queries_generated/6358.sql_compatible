SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.ClosedDate ELSE NULL END) AS LastClosedQuestion,
    MIN(ph.CreationDate) AS FirstPostHistory,
    MAX(ph.CreationDate) AS LastPostHistory,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId ELSE NULL END) AS TotalBadges,
    STRING_AGG(DISTINCT CASE WHEN t.TagName IS NOT NULL THEN t.TagName ELSE NULL END, ',') AS TaggedTopics
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT 
        pt.Id, 
        -- convert tags like '<tag1><tag2>' to array of tag texts in a dialect-neutral way
        REGEXP_REPLACE(pt.Tags, '^<|>$', '', 'g') AS TagString
    FROM Posts pt
    WHERE pt.PostTypeId = 1
) AS tg ON p.Id = tg.Id
LEFT JOIN 
    Tags t ON t.TagName = t.TagName -- placeholder to allow join below
    -- real join between TagString and Tags requires splitting TagString into rows;
    -- emulate by joining on INSTR/LIKE pattern matching for portability
    AND tg.TagString IS NOT NULL
    AND tg.TagString <> ''
    AND (   POSITION(('<' || t.TagName || '>') IN ('<' || REPLACE(tg.TagString, '><', '><') || '>')) > 0
        OR POSITION(t.TagName IN tg.TagString) > 0)
WHERE 
    u.Reputation > 100 
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
    AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC, 
    TotalPositiveScorePosts DESC;