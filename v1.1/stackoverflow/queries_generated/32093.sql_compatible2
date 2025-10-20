SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p.Id AS PostId,
    p.Score,
    p.CreationDate AS PostCreationDate,
    COALESCE(SUM(CASE WHEN vl.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
    COALESCE(SUM(CASE WHEN vl.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    COUNT(DISTINCT ph.Id) AS EditsCount,
    COUNT(DISTINCT vl.Id) AS TotalVotesCount,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    ARRAY_AGG(DISTINCT t.TagName) AS AssociatedTags
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes vl ON p.Id = vl.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT
        EXTRACT(EPOCH FROM (MAX(p2.LastActivityDate) - MIN(p2.CreationDate))) AS ActivitySpan,
        p2.OwnerUserId
    FROM 
        Posts p2
    GROUP BY 
        p2.OwnerUserId
) AS user_activity ON u.Id = user_activity.OwnerUserId
LEFT JOIN LATERAL (
    SELECT 
        tag_table.TagName
    FROM 
        Posts p3
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM s.tag_text) AS tag_text
        FROM (
            SELECT unnest(string_to_array(COALESCE(p3.Tags, ''), '><')) AS tag_text
        ) AS s
    ) AS split(tag_text)
    JOIN Tags tag_table ON tag_table.Id = CASE WHEN split.tag_text ~ '^[0-9]+$' THEN CAST(split.tag_text AS INTEGER) ELSE NULL END
    WHERE 
        p3.Id = p.Id
    LIMIT 1
) t ON TRUE
WHERE 
    u.CreationDate > DATE '2023-01-01'
    AND COALESCE(user_activity.ActivitySpan, 0) < 31536000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Score, p.CreationDate, user_activity.ActivitySpan
ORDER BY 
    p.Score DESC, UpVotesCount DESC, DownVotesCount ASC
LIMIT 50;