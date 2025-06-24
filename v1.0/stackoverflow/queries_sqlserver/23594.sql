
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
        p.OwnerUserId
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= DATEADD(year, -1, '2024-10-01') 
        AND p.PostTypeId = 1 
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount 
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.CreationDate < DATEADD(year, -2, '2024-10-01') 
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistoryAggregate AS (
    SELECT 
        ph.PostId,
        STRING_AGG(DISTINCT pht.Name, ',') AS HistoryTypes,
        COUNT(*) AS TotalChanges
    FROM 
        PostHistory ph
    JOIN 
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE 
        ph.CreationDate >= DATEADD(month, -6, '2024-10-01') 
    GROUP BY 
        ph.PostId
)
SELECT 
    ua.DisplayName,
    ua.QuestionCount,
    ua.CommentCount,
    ua.UpvoteCount,
    ua.DownvoteCount,
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    pha.HistoryTypes,
    pha.TotalChanges
FROM 
    UserActivity ua
JOIN 
    RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.PostRank <= 5
LEFT JOIN 
    PostHistoryAggregate pha ON rp.PostId = pha.PostId
WHERE 
    ua.UpvoteCount > ua.DownvoteCount
ORDER BY 
    ua.QuestionCount DESC, 
    rp.Score DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;
