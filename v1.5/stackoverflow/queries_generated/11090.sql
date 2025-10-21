-- {"query": "11090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 638} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts p
    INNER JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '30 days' 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
    FROM 
        Posts
    GROUP BY 
        UserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'') AS Tags
    FROM 
        Posts p
)
SELECT 
    RecentPosts.Id, 
    RecentPosts.Title, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    RecentPosts.VoteCount, 
    RecentPosts.UpVoteCount, 
    RecentPosts.DownVoteCount,
    COALESCE(TopUsers.PostCount, 0) AS TopUserPostCount,
    COALESCE(TopUsers.AvgScore, 0) AS TopUserAvgScore,
    STRING_AGG(DISTINCT pt.Tags, ', ') AS Tags
FROM 
    RecentPosts
LEFT JOIN 
    TopUsers ON RecentPosts.OwnerUserId = TopUsers.UserId
LEFT JOIN 
    PostTags pt ON RecentPosts.Id = pt.PostId
GROUP BY 
    RecentPosts.Id, RecentPosts.Title, RecentPosts.CreationDate, RecentPosts.Score, RecentPosts.ViewCount, RecentPosts.OwnerDisplayName, RecentPosts.OwnerReputation, RecentPosts.VoteCount, RecentPosts.UpVoteCount, RecentPosts.DownVoteCount, TopUsers.PostCount, TopUsers.AvgScore
ORDER BY 
    RecentPosts.Score DESC, 
    RecentPosts.ViewCount DESC, 
    RecentPosts.CreationDate DESC
LIMIT 10;
