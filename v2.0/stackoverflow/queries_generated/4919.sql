-- {"query": "4919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1632} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS TotalUpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS TotalDownVotes,
        COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN v.Id ELSE NULL END) AS TotalAcceptedVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(upa.TotalPostsOwned, 0) AS PostsOwned,
    COALESCE(upa.TotalQuestionsOwned, 0) AS QuestionsOwned,
    COALESCE(upa.TotalAnswersOwned, 0) AS AnswersOwned,
    COALESCE(upa.AvgPostScore, 0.0) AS AvgPostScore,
    upa.LatestPostDate,
    COALESCE(uca.TotalComments, 0) AS CommentsMade,
    COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
    uca.LatestCommentDate,
    COALESCE(uvs.TotalUpVotes, 0) AS VotesCastUp,
    COALESCE(uvs.TotalDownVotes, 0) AS VotesCastDown,
    COALESCE(uvs.TotalAcceptedVotes, 0) AS VotesCastAccepted,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadges,
    CASE
        WHEN EXISTS (SELECT 1 FROM RankedPostEdits rpe WHERE rpe.UserId = u.Id AND rpe.rn = 1)
        THEN (SELECT rpe.CreationDate FROM RankedPostEdits rpe WHERE rpe.UserId = u.Id AND rpe.rn = 1)
        ELSE u.CreationDate
    END AS LastActivityOrCreation,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Internal'
        WHEN u.WebsiteUrl IS NOT NULL THEN 'External'
        ELSE 'None'
    END AS WebsiteCategory,
    CASE
        WHEN u.AboutMe IS NULL OR LENGTH(TRIM(u.AboutMe)) = 0 THEN 'Empty'
        WHEN LENGTH(u.AboutMe) < 50 THEN 'Short'
        WHEN LENGTH(u.AboutMe) BETWEEN 50 AND 500 THEN 'Medium'
        ELSE 'Long'
    END AS AboutMeLength,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (1, 2, 3)
    ) AS InitialEditsCount,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS SubsequentEditsCount
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
WHERE u.Id < 1000000 AND u.Views > 500
UNION
SELECT
    NULL AS UserId,
    'Community User' AS DisplayName,
    COUNT(DISTINCT p.Id) AS PostsOwned,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.CreationDate) AS LatestPostDate,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    AVG(c.Score) AS AvgCommentScore,
    MAX(c.CreationDate) AS LatestCommentDate,
    COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS VotesCastUp,
    COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS VotesCastDown,
    COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN v.Id ELSE NULL END) AS VotesCastAccepted,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    MAX(p.CreationDate) AS LastActivityOrCreation,
    'N/A' AS WebsiteCategory,
    'N/A' AS AboutMeLength,
    COUNT(DISTINCT ph.PostId) AS InitialEditsCount,
    COUNT(DISTINCT ph.PostId) AS SubsequentEditsCount
FROM Posts p
LEFT JOIN Comments c ON p.OwnerUserId = c.UserId AND p.OwnerUserId = -1
LEFT JOIN Votes v ON p.OwnerUserId = v.UserId AND p.OwnerUserId = -1
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN PostHistory ph ON p.OwnerUserId = ph.UserId AND p.OwnerUserId = -1 AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
WHERE p.OwnerUserId = -1;