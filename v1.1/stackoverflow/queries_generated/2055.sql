-- {"query": "2055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 417} 

WITH HighReputationUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 10000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
    HAVING 
        COUNT(b.Id) > 5
),
MostActivePosts AS (
    SELECT 
        p.Id AS PostId, 
        p.OwnerUserId, 
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(c.Id) DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.OwnerUserId
),
PopularTags AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT pq.PostId) AS QuestionCount
    FROM 
        Tags t
    LEFT JOIN 
        Posts pq ON pq.Tags LIKE '%' || t.TagName || '%'
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(DISTINCT pq.PostId) > 50
)
SELECT 
    u.DisplayName,
    u.Reputation,
    hp.BadgeCount,
    mp.PostId,
    mp.CommentCount,
    pt.TagName
FROM 
    HighReputationUsers hp
JOIN 
    MostActivePosts mp ON hp.UserId = mp.OwnerUserId AND mp.rn = 1
LEFT JOIN 
    PopularTags pt ON EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = hp.UserId AND p.Tags LIKE '%' || pt.TagName || '%'
    )
ORDER BY 
    hp.Reputation DESC, 
    mp.CommentCount DESC;
