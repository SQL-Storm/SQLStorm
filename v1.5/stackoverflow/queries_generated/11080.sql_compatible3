WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS AuthorDisplayName,
        u.Reputation AS AuthorReputation
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
        AND p.PostTypeId = 1
),
PostVotes AS (
    SELECT 
        PostId,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Votes
    GROUP BY 
        PostId
),
PostTags AS (
    SELECT 
        p.Id AS PostId,
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
),
AuthorBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
)
SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.AuthorDisplayName,
    rp.AuthorReputation,
    pv.VoteCount,
    pv.UpvoteCount,
    pv.DownvoteCount,
    STRING_AGG(pt.TagName, ', ') AS Tags,
    COALESCE(ab.BadgeCount, 0) AS BadgeCount
FROM 
    RecentPosts rp
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    AuthorBadges ab ON rp.AuthorDisplayName = (
        SELECT u.DisplayName 
        FROM Users u 
        WHERE u.Reputation = rp.AuthorReputation
        LIMIT 1
    )
GROUP BY 
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.AuthorDisplayName,
    rp.AuthorReputation,
    pv.VoteCount,
    pv.UpvoteCount,
    pv.DownvoteCount,
    ab.BadgeCount
ORDER BY 
    rp.CreationDate DESC,
    rp.Score DESC,
    rp.ViewCount DESC
LIMIT 10;