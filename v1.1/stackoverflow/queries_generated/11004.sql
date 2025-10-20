-- {"query": "11004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 642} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days' 
        AND p.PostTypeId = 1
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalPosts, 
        SUM(Score) AS TotalScore, 
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    JOIN 
        Votes v ON p.Id = v.PostId
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        u.Id
),
PostTags AS (
    SELECT 
        p.Id, 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'') AS TagsArray
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TagCounts AS (
    SELECT 
        unnest(TagsArray) AS TagName, 
        COUNT(*) AS TagCount
    FROM 
        PostTags
    GROUP BY 
        TagName
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation,
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.UpVotes, 
    ua.DownVotes,
    STRING_AGG(DISTINCT tc.TagName, ', ') AS Tags
FROM 
    RecentPosts rp
JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    TagCounts tc ON pt.TagsArray = ANY(tc.TagName)
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.OwnerReputation, ua.TotalPosts, ua.TotalScore, ua.UpVotes, ua.DownVotes
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    ua.TotalScore DESC
LIMIT 10;
