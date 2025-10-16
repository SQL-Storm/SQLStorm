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
        p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        trim(tn) AS TagName
    FROM 
        Posts p,
        LATERAL (
            SELECT unnest(string_to_array(p.Tags, ',')) AS tn
        ) s
    JOIN 
        Tags t ON t.TagName = trim(s.tn)
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