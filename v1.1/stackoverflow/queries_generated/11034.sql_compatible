WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS RowNum
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        p.OwnerUserId AS UserId, 
        SUM(p.Score) AS TotalScore
    FROM 
        Posts p
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY 
        p.OwnerUserId
    HAVING 
        SUM(p.Score) > 100
    ORDER BY 
        TotalScore DESC
    LIMIT 10
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.VoteCount, 
    rp.UpvoteCount, 
    rp.DownvoteCount, 
    COALESCE(pa.CommentCount, 0) AS CommentCount, 
    COALESCE(pa.EditCount, 0) AS EditCount
FROM 
    RecentPosts rp
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.Id
WHERE 
    rp.RowNum = 1
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.AnswerCount DESC;