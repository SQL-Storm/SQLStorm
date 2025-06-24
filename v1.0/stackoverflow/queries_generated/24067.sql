WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
VoteSummary AS (
    SELECT 
        postId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes
    FROM 
        Votes v
    JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
        postId
),
UserBadges AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ') AS Badges,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
PostHistoryStats AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN ph.CreationDate END) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstHistoryDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    ps.EditCount,
    ps.LastEditDate,
    ps.FirstHistoryDate,
    COALESCE(vs.UpVotes, 0) AS TotalUpVotes,
    COALESCE(vs.DownVotes, 0) AS TotalDownVotes,
    ub.Badges,
    CASE 
        WHEN ub.BadgeCount = 0 THEN 'No Badges'
        WHEN ub.BadgeCount <= 3 THEN 'Few Badges'
        ELSE 'Many Badges'
    END AS BadgeCategory
FROM 
    RankedPosts rp
LEFT JOIN 
    VoteSummary vs ON rp.PostId = vs.postId
LEFT JOIN 
    PostHistoryStats ps ON rp.PostId = ps.PostId
LEFT JOIN 
    UserBadges ub ON rp.PostId IN (
        SELECT 
            OwnerUserId 
        FROM 
            Posts 
        WHERE 
            Id = rp.PostId
    )
WHERE
    rp.rn <= 5
ORDER BY 
    rp.CreationDate DESC,
    TotalUpVotes DESC,
    rp.Title ASC;

