-- {"query": "2066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 496} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.CreationDate, 
        p.PostTypeId, 
        p.Score, 
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year'
),
TopRecentPosts AS (
    SELECT 
        rp.Id, 
        rp.CreationDate, 
        rp.PostTypeId, 
        rp.Score
    FROM 
        RecentPosts rp
    WHERE 
        rp.PostRank <= 10
),
TaggedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') as TagArray,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND
        EXISTS (
            SELECT 1 
            FROM Tags t 
            WHERE 
                t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AND
                t.IsModeratorOnly = 0
        )
),
PopularTaggedQuestions AS (
    SELECT 
        tp.Id, 
        tp.Title
    FROM 
        TaggedPosts tp
    WHERE 
        tp.ScoreRank <= 5
)
SELECT 
    u.DisplayName, 
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    COALESCE(p.Title, 'No Title') AS PostTitle,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS LastUpvoteId
FROM 
    Users u
LEFT JOIN 
    TopRecentPosts rp ON rp.Id = u.Id
LEFT OUTER JOIN 
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id AND v.UserId = u.Id
INNER JOIN 
    PopularTaggedQuestions ptq ON ptq.Id = p.Id
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.DisplayName, u.Location, p.Title
ORDER BY 
    u.DisplayName;
