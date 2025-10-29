-- {"query": "4480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1682}
WITH RankedUserVotes AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        v.VoteTypeId,
        vt.Name AS VoteTypeName,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY COUNT(v.Id) DESC) AS rn
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE u.CreationDate < DATE '2010-01-01'
      AND u.Reputation > 10000
      AND vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY u.Id, u.DisplayName, v.VoteTypeId, vt.Name
),
TopUserVoteTypes AS (
    SELECT
        UserId,
        DisplayName,
        VoteTypeName,
        VoteCount,
        rn
    FROM RankedUserVotes
    WHERE rn <= 3
),
PostVoteAggregates AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS Favorites,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyAmount,
        COUNT(v.Id) AS TotalVotes -- needed for HAVING
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate BETWEEN DATE '2012-01-01' AND DATE '2013-01-01'
      AND p.Score > 5
    GROUP BY p.Id, p.Title, p.PostTypeId, pt.Name
    HAVING COUNT(v.Id) > 10
),
UsersWithManyEdits AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND COALESCE(u.DownVotes,0) < COALESCE(u.UpVotes,0) * 0.1
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(ph.Id) > 50
),
DetailedPostInfo AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        pva.UpVotes,
        pva.DownVotes,
        pva.Favorites,
        pva.TotalBountyAmount,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        (
            SELECT COUNT(c.Id)
            FROM Comments c
            WHERE c.PostId = p.Id
              AND c.Score > 0
              AND c.UserId IS NOT NULL
        ) AS HighScoreCommentCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN PostVoteAggregates pva ON p.Id = pva.PostId
    WHERE p.AnswerCount > 0
)
SELECT
    dpi.PostId,
    dpi.Title,
    dpi.PostStatus,
    dpi.OwnerDisplayName,
    dpi.UserLocation,
    dpi.UpVotes,
    dpi.DownVotes,
    dpi.Favorites,
    dpi.TotalBountyAmount,
    dpi.HighScoreCommentCount,
    tuvt.VoteTypeName AS TopVoteType1,
    tuvt.VoteCount AS TopVoteCount1,
    COALESCE(u2.DisplayName, 'No Last Editor') AS LastEditorDisplayName,
    SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN p.Tags) - 2)) AS FirstTag,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 3) THEN 'HasDuplicateLink'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 1) THEN 'HasLinkedPost'
        ELSE 'NoLinks'
    END AS LinkStatus
FROM DetailedPostInfo dpi
LEFT JOIN TopUserVoteTypes tuvt ON dpi.OwnerUserId = tuvt.UserId AND tuvt.rn = 1
LEFT JOIN Users u2 ON dpi.OwnerUserId = u2.Id
LEFT JOIN Posts p ON dpi.PostId = p.Id
WHERE dpi.CreationDate > DATE '2012-06-01'
  AND dpi.TotalBountyAmount > 0
  AND LENGTH(dpi.Title) > 20
  AND dpi.UserLocation IS NOT NULL
  AND dpi.PostStatus <> 'Closed'
UNION
SELECT
    dpi.PostId,
    dpi.Title,
    dpi.PostStatus,
    dpi.OwnerDisplayName,
    dpi.UserLocation,
    dpi.UpVotes,
    dpi.DownVotes,
    dpi.Favorites,
    dpi.TotalBountyAmount,
    dpi.HighScoreCommentCount,
    tuvt.VoteTypeName AS TopVoteType1,
    tuvt.VoteCount AS TopVoteCount1,
    COALESCE(u2.DisplayName, 'No Last Editor') AS LastEditorDisplayName,
    SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN p.Tags) - 2)) AS FirstTag,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 3) THEN 'HasDuplicateLink'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 1) THEN 'HasLinkedPost'
        ELSE 'NoLinks'
    END AS LinkStatus
FROM DetailedPostInfo dpi
JOIN UsersWithManyEdits uwe ON dpi.OwnerUserId = uwe.UserId
LEFT JOIN TopUserVoteTypes tuvt ON dpi.OwnerUserId = tuvt.UserId AND tuvt.rn = 1
LEFT JOIN Users u2 ON dpi.OwnerUserId = u2.Id
LEFT JOIN Posts p ON dpi.PostId = p.Id
WHERE dpi.Favorites > 100
  AND uwe.EditCount > 100
  AND uwe.LastEditDate > DATE '2013-01-01'
ORDER BY UpVotes DESC, Favorites DESC
LIMIT 1000;