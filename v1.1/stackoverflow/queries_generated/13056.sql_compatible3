WITH UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR)
    GROUP BY 
        u.Id, u.DisplayName
),
TopEditors AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS EditCount
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6)
        AND EXTRACT(MONTH FROM ph.CreationDate) = EXTRACT(MONTH FROM CAST('2024-10-01' AS date))
    GROUP BY 
        ph.UserId
    ORDER BY 
        EditCount DESC
    LIMIT 10
),
PostSummary AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score,
        p.OwnerUserId,
        ph.Comment AS CloseReason,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName), 'No Tags') AS TagList,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(pl.Id) AS LinkCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN 
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN 
        Tags t ON POSITION(t.TagName IN p.Tags) > 0
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id, p.Title, p.Score, p.OwnerUserId, ph.Comment
    HAVING 
        COUNT(pl.Id) > 0
)
SELECT 
    ua.DisplayName,
    ua.PostsCount,
    ua.PositiveScorePosts,
    ua.LastPostDate,
    te.EditCount,
    ps.Title,
    ps.Score,
    ps.TagList,
    ps.UpVotes,
    ps.DownVotes,
    ROUND(
      (CAST(ps.UpVotes AS DECIMAL) / NULLIF(ps.UpVotes + ps.DownVotes, 0)) * 100
    , 2) AS PositiveFeedbackRate,
    ua.Id,
    ua.ActivityRank
FROM 
    UserActivity ua
JOIN 
    TopEditors te ON ua.Id = te.UserId
LEFT JOIN 
    PostSummary ps ON ua.Id = ps.OwnerUserId
WHERE 
    ua.ActivityRank <= 50
    AND (ps.Score > 50 OR ps.Score IS NULL)
ORDER BY 
    ua.ActivityRank, te.EditCount DESC;