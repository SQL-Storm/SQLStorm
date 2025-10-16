-- {"query": "12036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 811} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS UserPostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1
),
TopPosts AS (
    SELECT 
        Id, 
        Title, 
        Score, 
        ViewCount, 
        CreationDate, 
        OwnerUserId, 
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
),
AggregatedData AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN rp.UserPostRank = 1 THEN rp.Id ELSE NULL END) AS TopRankedPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM 
        Users u
    LEFT JOIN 
        RankedPosts rp ON u.Id = rp.OwnerUserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS RevisionCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastEditBodyDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate ELSE NULL END) AS LastEditTagsDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
),
CommentCounts AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
PostDetails AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        phs.RevisionCount,
        phs.LastEditBodyDate,
        phs.LastEditTagsDate,
        cc.CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistorySummary phs ON p.Id = phs.PostId
    LEFT JOIN 
        CommentCounts cc ON p.Id = cc.PostId
)
SELECT 
    ad.UserId,
    ad.DisplayName,
    ad.Reputation,
    ad.TopRankedPosts,
    ad.Upvotes,
    ad.Downvotes,
    ad.BadgesEarned,
    pd.Id AS PostId,
    pd.Title,
    pd.Score,
    pd.ViewCount,
    pd.CreationDate,
    pd.OwnerUserId,
    pd.RevisionCount,
    pd.LastEditBodyDate,
    pd.LastEditTagsDate,
    pd.CommentCount
FROM 
    AggregatedData ad
JOIN 
    PostDetails pd ON ad.UserId = pd.OwnerUserId
WHERE 
    pd.Score > 10
ORDER BY 
    ad.Reputation DESC, 
    pd.Score DESC;