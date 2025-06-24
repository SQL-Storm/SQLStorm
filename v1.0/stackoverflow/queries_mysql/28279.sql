
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        TIMESTAMPDIFF(MINUTE, p.CreationDate, NOW()) AS AgeInMinutes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY TIMESTAMPDIFF(MINUTE, p.CreationDate, NOW()) DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) 
    GROUP BY 
        p.Id, p.Title, p.Body, p.Tags, u.DisplayName, p.CreationDate
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Body,
        rp.Tags,
        rp.OwnerDisplayName,
        rp.CreationDate,
        rp.AgeInMinutes,
        rp.UpVotes,
        rp.DownVotes,
        rp.CommentCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank = 1 
)
SELECT 
    fp.PostId,
    fp.Title,
    fp.OwnerDisplayName,
    fp.CreationDate,
    fp.AgeInMinutes,
    fp.UpVotes - fp.DownVotes AS NetVotes,
    fp.CommentCount,
    GROUP_CONCAT(DISTINCT t.TagName SEPARATOR ', ') AS TagsList
FROM 
    FilteredPosts fp
LEFT JOIN 
    Tags t ON LOCATE(t.TagName, TRIM(BOTH ',' FROM fp.Tags)) > 0
GROUP BY 
    fp.PostId, fp.Title, fp.OwnerDisplayName, fp.CreationDate, 
    fp.AgeInMinutes, fp.UpVotes, fp.DownVotes, fp.CommentCount
ORDER BY 
    NetVotes DESC, fp.CreationDate DESC
LIMIT 100;
