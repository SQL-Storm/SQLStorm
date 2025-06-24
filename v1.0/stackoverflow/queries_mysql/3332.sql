
WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL 30 DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.ViewCount
), 
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        @rownum := @rownum + 1 AS ReputationRank
    FROM 
        Users u, (SELECT @rownum := 0) r
    ORDER BY 
        u.Reputation DESC
), 
PostRanked AS (
    SELECT 
        rp.*,
        ur.DisplayName AS OwnerDisplayName,
        ur.Reputation AS OwnerReputation,
        ur.ReputationRank
    FROM 
        RecentPosts rp
    JOIN 
        UserReputation ur ON rp.OwnerUserId = ur.UserId
)
SELECT 
    pr.PostId,
    pr.Title,
    pr.CreationDate,
    pr.ViewCount,
    pr.CommentCount,
    pr.UpVotes,
    pr.DownVotes,
    pr.OwnerDisplayName,
    pr.OwnerReputation,
    pr.ReputationRank,
    COALESCE(bg.Id, 0) AS BadgeId,
    COALESCE(bg.Name, 'No Badge') AS BadgeName
FROM 
    PostRanked pr
LEFT JOIN 
    Badges bg ON pr.OwnerUserId = bg.UserId AND bg.Class = 1 
WHERE 
    pr.ViewCount > (
        SELECT AVG(ViewCount) 
        FROM RecentPosts
    )
ORDER BY 
    pr.ReputationRank,
    pr.ViewCount DESC
LIMIT 10;
