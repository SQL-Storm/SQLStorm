-- {"query": "11082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 643} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id, 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'') AS Tags
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TagFrequency AS (
    SELECT 
        unnest(Tags) AS TagName, 
        COUNT(*) AS Frequency
    FROM 
        PostTags
    GROUP BY 
        TagName
),
PostActivity AS (
    SELECT 
        p.Id, 
        COUNT(DISTINCT ph.CreationDate) AS EditCount, 
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TotalBounty, 
    pt.EditCount, 
    pt.CommentCount, 
    tf.TagName, 
    tf.Frequency
FROM 
    RecentPosts rp
JOIN 
    PostActivity pt ON rp.Id = pt.Id
LEFT JOIN 
    TagFrequency tf ON rp.Id = tf.PostId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    tf.Frequency DESC
LIMIT 100;
