
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        STRING_AGG(DISTINCT pt.Name, ',') AS PostTypeNames,
        STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
        p.OwnerUserId
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    CROSS APPLY 
        STRING_SPLIT(p.Tags, '>') AS tag
    LEFT JOIN 
        Tags t ON tag.value = t.TagName
    GROUP BY 
        p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.ViewCount, p.Score
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        SUM(u.UpVotes) AS TotalUpVotes,
        SUM(u.DownVotes) AS TotalDownVotes
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    p.PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.VoteCount,
    p.PostTypeNames,
    p.Tags,
    u.UserId,
    u.DisplayName,
    u.BadgeCount,
    u.TotalUpVotes,
    u.TotalDownVotes
FROM 
    PostStats p
JOIN 
    UserStats u ON p.OwnerUserId = u.UserId
ORDER BY 
    p.Score DESC, p.ViewCount DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
