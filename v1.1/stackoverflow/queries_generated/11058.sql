-- {"query": "11058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 905} 

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
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS DownVotes
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId, 
        SUM(Reputation) AS TotalReputation
    FROM 
        Users
    GROUP BY 
        UserId
    ORDER BY 
        TotalReputation DESC
    LIMIT 10
),
PostTags AS (
    SELECT 
        p.Id, 
        TRIM(BOTH '<' FROM SPLIT_PART(p.Tags, ',', generate_series(1, array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><''), 1)))) AS Tag
    FROM 
        Posts p,
        generate_series(1, array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><''), 1))
),
PostTagCounts AS (
    SELECT 
        pt.Id AS PostId, 
        pt.Tag, 
        COUNT(*) AS TagCount
    FROM 
        PostTags pt
    GROUP BY 
        pt.Id, pt.Tag
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS DownVotes,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY c.CreationDate DESC) AS CommentRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
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
    rp.UpVotes, 
    rp.DownVotes, 
    ptc.Tag, 
    ptc.TagCount, 
    pa.CommentCount, 
    pa.CommentRank
FROM 
    RecentPosts rp
JOIN 
    PostTagCounts ptc ON rp.Id = ptc.PostId
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.PostId
WHERE 
    ptc.TagCount > 1
    AND pa.CommentRank <= 3
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC
LIMIT 20;
