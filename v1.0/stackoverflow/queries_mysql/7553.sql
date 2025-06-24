
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes, 
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        @row_number := @row_number + 1 AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    CROSS JOIN (SELECT @row_number := 0) r
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName
),
ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        @reputation_rank := @reputation_rank + 1 AS ReputationRank
    FROM 
        Users u
    CROSS JOIN (SELECT @reputation_rank := 0) r
    WHERE 
        u.LastAccessDate >= NOW() - INTERVAL 30 DAY
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerDisplayName,
    rp.AnswerCount,
    rp.UpVotes,
    rp.DownVotes,
    au.DisplayName AS ActiveUserDisplayName,
    au.Reputation,
    au.ReputationRank
FROM 
    RankedPosts rp
LEFT JOIN 
    ActiveUsers au ON rp.OwnerUserId = au.UserId
WHERE 
    rp.PostRank <= 100
ORDER BY 
    rp.CreationDate DESC, rp.UpVotes DESC;
