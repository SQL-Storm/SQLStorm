WITH User_votes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY v.UserId
),
User_badges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
Popular_tags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount
    FROM Tags t
    JOIN Posts p ON CAST(p.Tags AS TEXT) LIKE '%' || CAST(',' || t.Id || ',' AS TEXT) || '%'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
),
Post_details AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Tags
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    uv.UpVotes AS UserUpVotes,
    uv.DownVotes AS UserDownVotes,
    ub.BadgeCount,
    ub.BadgeNames,
    pd.PostId,
    pd.Title,
    pd.UpVotes AS PostUpVotes,
    pd.DownVotes AS PostDownVotes,
    pd.CreationDate,
    pt.TagName
FROM Users u
LEFT JOIN User_votes uv ON u.Id = uv.UserId
LEFT JOIN User_badges ub ON u.Id = ub.UserId
JOIN Post_details pd ON u.Id = pd.OwnerUserId
LEFT JOIN Popular_tags pt ON pd.Tags LIKE '%' || pt.TagName || '%'
WHERE 
    (uv.UpVotes > 0 OR uv.DownVotes > 0)
    AND (ub.BadgeCount IS NOT NULL OR ub.BadgeCount > 0)
ORDER BY 
    u.Reputation DESC,
    pd.UpVotes DESC NULLS LAST,
    pd.CreationDate DESC
LIMIT 100;