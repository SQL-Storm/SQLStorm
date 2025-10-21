WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON v.PostId = p.Id
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId
),
UserWithMostPosts AS (
    SELECT 
        OwnerUserId, 
        COUNT(PostId) AS TotalPosts
    FROM 
        RankedPosts
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(PostId) > 5
),
TopRankedPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.UpVotes,
        rp.DownVotes,
        rp.CommentCount,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY rp.UpVotes DESC) AS VoteRank
    FROM 
        RankedPosts rp
    JOIN 
        Users u ON rp.OwnerUserId = u.Id
    WHERE 
        rp.PostRank = 1
        AND rp.OwnerUserId IN (SELECT OwnerUserId FROM UserWithMostPosts)
)
SELECT 
    trp.Title,
    trp.UpVotes,
    trp.DownVotes,
    trp.CommentCount,
    trp.DisplayName,
    trp.Reputation,
    CASE 
        WHEN trp.VoteRank <= 10 THEN 'Top 10 Post'
        ELSE 'Other Post'
    END AS RankCategory
FROM 
    TopRankedPosts trp
ORDER BY 
    trp.UpVotes DESC, 
    trp.CommentCount DESC;