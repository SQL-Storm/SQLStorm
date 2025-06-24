WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank,
        COUNT(c.Id) AS CommentCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,
        SUM(v.VoteTypeId = 3) AS DownVotes,
        CASE 
            WHEN SUM(v.VoteTypeId = 2) - SUM(v.VoteTypeId = 3) > 0 THEN 'Positive'
            WHEN SUM(v.VoteTypeId = 2) - SUM(v.VoteTypeId = 3) < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS VoteSentiment
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId
),
TotalVotes AS (
    SELECT 
        PostId,
        COUNT(*) AS TotalVoteCount
    FROM 
        Votes
    GROUP BY 
        PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.UpVotes,
    rp.DownVotes,
    tv.TotalVoteCount,
    rp.VoteSentiment
FROM 
    RankedPosts rp
LEFT JOIN 
    TotalVotes tv ON rp.PostId = tv.PostId
WHERE 
    rp.Rank <= 5
ORDER BY 
    rp.ViewCount DESC NULLS LAST;
