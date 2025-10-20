-- {"query": "11044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 957} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBountyAmount
    FROM 
        Posts p
    JOIN 
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
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
),
PostHistoryCTE AS (
    SELECT 
        ph.PostId, 
        ph.PostHistoryTypeId, 
        ph.CreationDate, 
        ph.UserId, 
        ph.UserDisplayName, 
        ph.Text, 
        ph.Comment
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate > CURRENT_DATE - INTERVAL '6 months'
),
TopAuthors AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(p.Id) AS PostCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(p.Id) > 10
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.LastEditDate, 
        p.LastActivityDate, 
        p.Score, 
        p.ViewCount, 
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AuthorDisplayName, 
    rp.Reputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.HighestBountyAmount, 
    STRING_AGG(DISTINCT pt.TagName, ', ') AS Tags, 
    STRING_AGG(DISTINCT ph.Comment, ', ' ORDER BY ph.CreationDate DESC) AS RecentHistory,
    pa.EditCount AS ActivityCount,
    ta.DisplayName AS TopAuthorDisplayName
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    PostHistoryCTE ph ON rp.Id = ph.PostId
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.Id
LEFT JOIN 
    TopAuthors ta ON rp.Id = ta.Id
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AuthorDisplayName, rp.Reputation, rp.VoteCount, rp.UpVoteCount, rp.DownVoteCount, rp.HighestBountyAmount, pa.EditCount, ta.DisplayName
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 100;
