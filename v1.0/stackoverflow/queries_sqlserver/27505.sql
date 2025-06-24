
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        COUNT(a.Id) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1 /* Considering only questions */
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, u.DisplayName
), FilteredPosts AS (
    SELECT 
        rp.*,
        (UpVoteCount - DownVoteCount) AS NetVoteCount
    FROM 
        RankedPosts rp
    WHERE 
        AnswerCount > 0 
    ORDER BY 
        NetVoteCount DESC
)
SELECT 
    fp.PostId,
    fp.Title,
    fp.OwnerName,
    fp.CreationDate,
    fp.AnswerCount,
    fp.CommentCount,
    fp.NetVoteCount
FROM 
    FilteredPosts fp
WHERE 
    fp.rn = 1 
    AND fp.CreationDate > DATEADD(year, -1, '2024-10-01 12:34:56') 
ORDER BY 
    fp.NetVoteCount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
