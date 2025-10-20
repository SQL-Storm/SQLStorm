-- {"query": "11050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 833} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS MaxBountyAmount
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
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        t.TagName
    FROM 
        Posts p
    CROSS JOIN 
        UNNEST(string_to_array(p.Tags, ',')) AS TagName
    JOIN 
        Tags t ON t.TagName = TagName
),
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        u.Views, 
        u.UpVotes, 
        u.DownVotes, 
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
    HAVING 
        COUNT(DISTINCT p.Id) > 10
    ORDER BY 
        u.Reputation DESC
    LIMIT 10
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.MaxBountyAmount,
    STRING_AGG(pt.TagName, ', ') AS Tags,
    tu.DisplayName AS TopUserDisplayName, 
    tu.Reputation AS TopUserReputation,
    tu.Views AS TopUserViews,
    tu.UpVotes AS TopUserUpVotes,
    tu.DownVotes AS TopUserDownVotes,
    tu.PostCount AS TopUserPostCount
FROM 
    RecentPosts rp
LEFT JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    TopUsers tu ON rp.OwnerDisplayName = tu.DisplayName
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.VoteCount, rp.UpVoteCount, rp.DownVoteCount, rp.MaxBountyAmount, tu.DisplayName, tu.Reputation, tu.Views, tu.UpVotes, tu.DownVotes, tu.PostCount
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 20;
