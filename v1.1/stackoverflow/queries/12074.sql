-- {"query": "12074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 761} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId IN (1, 2) AND p.Score > 0
),
TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.UpVotes,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS HistoryCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate END) AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS CloseDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
),
PostComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
PostVotes AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Votes v
    GROUP BY 
        v.PostId
)
SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.OwnerDisplayName,
    rp.Rank,
    tu.DisplayName AS TopUser,
    tu.Reputation,
    tu.BadgeCount,
    tu.UserRank,
    phs.HistoryCount,
    phs.LastEditDate,
    phs.CloseDate,
    pc.CommentCount,
    pc.AvgCommentScore,
    pv.VoteCount,
    pv.UpVoteCount,
    pv.DownVoteCount
FROM 
    RankedPosts rp
JOIN 
    TopUsers tu ON rp.OwnerDisplayName = tu.DisplayName
LEFT JOIN 
    PostHistorySummary phs ON rp.Id = phs.PostId
LEFT JOIN 
    PostComments pc ON rp.Id = pc.PostId
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId
WHERE 
    rp.Rank <= 10 AND tu.UserRank <= 10
ORDER BY 
    rp.Score DESC, rp.CreationDate;