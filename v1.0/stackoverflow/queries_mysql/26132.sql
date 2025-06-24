
WITH FilteredPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        GROUP_CONCAT(t.TagName SEPARATOR ', ') AS Tags
    FROM 
        Posts p
    JOIN 
        (SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(p.Tags, '><', n.n), '><', -1) AS tag_name
         FROM Posts p
         JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n
         ON CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '><', '')) >= n.n - 1) AS tag_name
    ON 
        true
    JOIN 
        Tags t ON t.TagName = tag_name
    WHERE 
        p.CreationDate >= '2023-10-01 12:34:56'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score
),
PostVoteCounts AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN VoteTypeId = 6 THEN 1 END) AS CloseVotes
    FROM 
        Votes
    GROUP BY 
        PostId
),
PostBadges AS (
    SELECT 
        u.Id AS UserId,
        GROUP_CONCAT(b.Name SEPARATOR ', ') AS BadgeNames
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    WHERE 
        b.Class = 1 
    GROUP BY 
        u.Id
)
SELECT 
    fp.PostId, 
    fp.Title, 
    fp.CreationDate, 
    fp.ViewCount, 
    fp.Score, 
    fp.Tags,
    pvc.UpVotes,
    pvc.DownVotes,
    pvc.CloseVotes,
    pb.BadgeNames
FROM 
    FilteredPosts fp
LEFT JOIN 
    PostVoteCounts pvc ON fp.PostId = pvc.PostId
LEFT JOIN 
    Users u ON u.Id = fp.PostId  
LEFT JOIN 
    PostBadges pb ON u.Id = pb.UserId
WHERE 
    fp.Score > 0
ORDER BY 
    fp.ViewCount DESC, 
    fp.Score DESC
LIMIT 50;
