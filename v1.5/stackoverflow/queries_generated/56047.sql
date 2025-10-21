-- {"query": "56047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 292} 

WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(p.Id) AS post_count
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1 AND p.Score > 10
    GROUP BY 
        u.Id, u.DisplayName
    ORDER BY 
        post_count DESC
    LIMIT 10
),
top_tags AS (
    SELECT 
        t.TagName, 
        COUNT(p.Id) AS post_count
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE '%' + t.TagName + '%'
    WHERE 
        p.PostTypeId = 1 AND p.Score > 10
    GROUP BY 
        t.TagName
    ORDER BY 
        post_count DESC
    LIMIT 10
)
SELECT 
    tu.DisplayName AS top_user, 
    tt.TagName AS top_tag, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount
FROM 
    Posts p
JOIN 
    top_users tu ON p.OwnerUserId = tu.Id
JOIN 
    top_tags tt ON p.Tags LIKE '%' + tt.TagName + '%'
WHERE 
    p.PostTypeId = 1 AND p.Score > 10
ORDER BY 
    p.Score DESC, p.ViewCount DESC;
