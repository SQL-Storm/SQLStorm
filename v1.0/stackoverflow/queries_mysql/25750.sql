
WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        COUNT(a.Id) AS AnswerCount,
        GROUP_CONCAT(DISTINCT u.DisplayName ORDER BY u.DisplayName SEPARATOR ', ') AS TopContributors,
        COALESCE(MAX(v.CreationDate), '1900-01-01') AS LastVoteDate
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Users u ON u.Id = p.OwnerUserId
    WHERE 
        p.CreationDate >= '2024-10-01 12:34:56' - INTERVAL 30 DAY
    GROUP BY 
        p.Id, p.Title, p.Tags, p.CreationDate
),
PostDetails AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Tags,
        rp.CreationDate,
        rp.AnswerCount,
        rp.TopContributors,
        rp.LastVoteDate,
        CASE 
            WHEN rp.AnswerCount > 5 THEN 'Hot'
            WHEN rp.LastVoteDate >= '2024-10-01 12:34:56' - INTERVAL 2 DAY THEN 'Trending'
            ELSE 'Regular' 
        END AS PostStatus
    FROM 
        RecentPosts rp
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.Tags,
    pd.CreationDate,
    pd.AnswerCount,
    pd.TopContributors,
    pd.PostStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pd.PostId) AS CommentCount
FROM 
    PostDetails pd
WHERE 
    pd.PostStatus IN ('Hot', 'Trending')
ORDER BY 
    pd.CreationDate DESC;
