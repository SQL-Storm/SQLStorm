-- {"query": "4480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1682} 
WITH RankedUserVotes AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        v.VoteTypeId,
        vt.Name AS VoteTypeName,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY COUNT(v.Id) DESC) as rn
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE u.CreationDate < '2010-01-01'
      AND u.Reputation > 10000
      AND vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY u.Id, u.DisplayName, v.VoteTypeId, vt.Name
),
TopUserVoteTypes AS (
    SELECT
        UserId,
        DisplayName,
        VoteTypeName,
        VoteCount
    FROM RankedUserVotes
    WHERE rn <= 3
),
PostVoteAggregates AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS DownVotes,
        COUNT(DISTINCT CASE WHEN vt.Name = 'Favorite' THEN v.Id ELSE NULL END) AS Favorites,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate BETWEEN '2012-01-01' AND '2013-01-01'
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
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
      AND u.DownVotes < u.UpVotes * 0.1
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(ph.Id) > 50
),
DetailedPostInfo AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
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
    -- Simple string manipulation to extract a tag
    SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2) AS FirstTag,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 3) THEN 'HasDuplicateLink'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 1) THEN 'HasLinkedPost'
        ELSE 'NoLinks'
    END AS LinkStatus
FROM DetailedPostInfo dpi
LEFT JOIN TopUserVoteTypes tuvt ON dpi.OwnerUserId = tuvt.UserId AND tuvt.rn = 1
LEFT JOIN Users u2 ON dpi.OwnerUserId = u2.Id -- Alias u2 to avoid conflict, though not strictly needed if LastEditorUserId was used and not OwnerUserId
LEFT JOIN Posts p ON dpi.PostId = p.Id
WHERE dpi.CreationDate > '2012-06-01'
  AND dpi.TotalBountyAmount > 0
  AND LENGTH(dpi.Title) > 20
  AND dpi.UserLocation IS NOT NULL
  AND dpi.PostStatus != 'Closed'
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
    SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2) AS FirstTag,
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
  AND uwe.LastEditDate > '2013-01-01'
ORDER BY dpi.UpVotes DESC, dpi.Favorites DESC
LIMIT 1000;