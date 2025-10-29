-- {"query": "4278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1228} 
WITH PostScoreAndCommentCount AS (
    SELECT
        p.Id AS PostId,
        p.Score,
        p.CommentCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CommentCount DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END ORDER BY p.Score DESC) AS ClosedScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(c.Id) AS TotalComments
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName
),
TopUsersWithBadges AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.TotalPosts,
        upa.TotalScore,
        upa.AvgViewCount,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM UserPostActivity upa
    LEFT JOIN Badges b ON upa.UserId = b.UserId AND b.Class IN (1, 2) -- Gold or Silver badges
    GROUP BY upa.UserId, upa.DisplayName, upa.TotalPosts, upa.TotalScore, upa.AvgViewCount
    HAVING COUNT(b.Id) >= 5
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN ph.Id END) AS TitleEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN ph.Id END) AS BodyEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN ph.CreationDate END) AS LastCloseVoteDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedCount
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    pscc.PostId,
    pscc.Score,
    pscc.CommentCount,
    pscc.IsClosed,
    pscc.ScoreRank,
    pscc.ClosedScoreRank,
    tuwb.DisplayName AS TopUserDisplayName,
    tuwb.TotalPosts,
    tuwb.TotalScore,
    tuwb.AvgViewCount,
    tuwb.TotalBadges,
    pha.TitleEdits,
    pha.BodyEdits,
    pha.LastCloseVoteDate,
    pha.CommunityOwnedCount,
    CASE
        WHEN pha.CommunityOwnedCount > 0 THEN 'Community Owned'
        WHEN pscc.Score > 1000 AND pha.BodyEdits < 5 THEN 'Highly Scored, Minimal Edits'
        WHEN pscc.IsClosed = 1 AND pha.LastCloseVoteDate IS NOT NULL THEN 'Closed and Voted'
        ELSE 'Standard Post'
    END AS PostCategory,
    COALESCE(p.Title, 'No Title') AS PostTitle,
    UPPER(SUBSTRING(p.ContentLicense FROM 1 FOR 3)) AS LicenseAbbreviation,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pscc.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    p.CreationDate AS PostCreationDate,
    u.CreationDate AS OwnerCreationDate
FROM PostScoreAndCommentCount pscc
JOIN Posts p ON pscc.PostId = p.Id
LEFT JOIN PostHistoryAnalysis pha ON pscc.PostId = pha.PostId
LEFT JOIN TopUsersWithBadges tuwb ON p.OwnerUserId = tuwb.UserId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE pscc.ScoreRank <= 100 -- Top 100 posts by score
UNION
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL,
    upa.DisplayName,
    upa.TotalPosts,
    upa.TotalScore,
    upa.AvgViewCount,
    COUNT(b.Id),
    NULL, NULL, NULL, NULL,
    'User Activity Summary',
    NULL, NULL, NULL, NULL, NULL
FROM UserPostActivity upa
LEFT JOIN Badges b ON upa.UserId = b.UserId
GROUP BY upa.UserId, upa.DisplayName, upa.TotalPosts, upa.TotalScore, upa.AvgViewCount
HAVING upa.TotalPosts > 500 -- Users with more than 500 posts
ORDER BY PostCategory DESC, Score DESC, PostCreationDate DESC;