-- {"query": "32093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 497} 

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p.Id AS PostId,
    p.Score,
    p.CreationDate AS PostCreationDate,
    COALESCE(SUM(CASE WHEN vl.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
    COALESCE(SUM(CASE WHEN vl.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    COUNT(DISTINCT ph.Id) AS EditsCount,
    COUNT(DISTINCT vl.Id) AS TotalVotesCount,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    ARRAY_AGG(DISTINCT t.TagName) AS AssociatedTags
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes vl ON p.Id = vl.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT
         EXTRACT(EPOCH FROM(MAX(p.LastActivityDate) - MIN(p.CreationDate))) AS ActivitySpan,
         p.OwnerUserId
     FROM 
         Posts p
     GROUP BY 
         p.OwnerUserId) AS user_activity ON u.Id = user_activity.OwnerUserId
LEFT JOIN 
    LATERAL (
        SELECT 
            t.TagName 
        FROM 
            Posts p2
        JOIN 
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '><' FROM p2.Tags), '><')) AS t(tag_id) 
        JOIN 
            Tags t ON t.id = tag_id::INTEGER
        WHERE 
            p2.Id = p.Id
    ) t
ON TRUE
WHERE 
    u.CreationDate > '2023-01-01' AND user_activity.ActivitySpan < 31536000  -- Less than one year in seconds
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Score, p.CreationDate
ORDER BY 
    p.Score DESC, UpVotesCount DESC, DownVotesCount ASC
LIMIT 50;
