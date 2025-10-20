WITH RECURSIVE RecursiveAncestorPaths AS (
    SELECT
        p.Id AS PostId,
        p.ParentId,
        ARRAY[p.Id] AS AncestorPath
    FROM Posts p
    WHERE p.PostTypeId = 2

    UNION ALL

    SELECT
        r.PostId,
        p.ParentId,
        r.AncestorPath || p.ParentId
    FROM RecursiveAncestorPaths r
    JOIN Posts p ON p.Id = r.ParentId
    WHERE p.ParentId IS NOT NULL
),
AtomicAskers AS (
    SELECT DISTINCT OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL AND OwnerUserId <> -1
),
Time_WindowedBadges AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS rn
    FROM Badges b
    WHERE b.Name IS NOT NULL
),
ComplexVotesInfoForPosts AS (
    SELECT
        p.Id AS PostId,
        COALESCE(MAX(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END), 0) AS HasUpMode,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpModCount,
        SUM(COALESCE(m.InnerVoteCount, 0)) AS TotalInnerVoteCount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS InnerVoteCount
        FROM Votes
        GROUP BY PostId
    ) m ON m.PostId = p.Id
    GROUP BY p.Id
)
SELECT
    p.Id AS PostId,
    p.ParentId,
    p.OwnerUserId,
    r.AncestorPath,
    a.OwnerUserId AS AskerUserId,
    b.UserId AS BadgeUserId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    c.HasUpMode,
    c.UpModCount,
    c.TotalInnerVoteCount
FROM Posts p
LEFT JOIN RecursiveAncestorPaths r ON r.PostId = p.Id
LEFT JOIN AtomicAskers a ON a.OwnerUserId = p.OwnerUserId
LEFT JOIN Time_WindowedBadges b ON b.UserId = p.OwnerUserId AND b.rn = 1
LEFT JOIN ComplexVotesInfoForPosts c ON c.PostId = p.Id
WHERE p.PostTypeId IN (1, 2)
GROUP BY
    p.Id,
    p.ParentId,
    p.OwnerUserId,
    r.AncestorPath,
    a.OwnerUserId,
    b.UserId,
    b.Name,
    b.Class,
    b.Date,
    c.HasUpMode,
    c.UpModCount,
    c.TotalInnerVoteCount;