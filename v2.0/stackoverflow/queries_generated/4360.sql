-- {"query": "4360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1637} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(cr.Name, 'Not Closed') AS CloseReason,
        COUNT(DISTINCT pc.Id) AS CommentCountOnPost,
        SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnPost,
        SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnPost,
        CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Is Duplicate' ELSE 'Not Duplicate' END AS DuplicateStatus
    FROM Posts p
    LEFT JOIN CloseReasonTypes cr ON p.ClosedDate IS NOT NULL AND cr.Id = (
        SELECT ph.Comment
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    )
    LEFT JOIN Comments pc ON p.Id = pc.PostId
    LEFT JOIN Votes pv ON p.Id = pv.PostId AND pv.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, CloseReason
)
SELECT
    ua.DisplayName AS UserDisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalUpVotesReceived,
    ua.TotalDownVotesReceived,
    pe.Title AS PostTitle,
    pe.PostCreationDate,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCount AS PostCommentCount,
    pe.FavoriteCount AS PostFavoriteCount,
    pe.CloseReason,
    pe.CommentCountOnPost,
    pe.UpVotesOnPost,
    pe.DownVotesOnPost,
    pe.DuplicateStatus,
    rpe.CreationDate AS LastEditDate,
    CASE WHEN ua.LastPostCreationDate > pe.PostCreationDate THEN 'Older Post' ELSE 'Newer Post' END AS PostAgeRelative,
    LENGTH(pe.Title) AS TitleLength,
    UPPER(SUBSTRING(pe.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE WHEN pe.PostScore > 100 THEN 'High Score' WHEN pe.PostScore < 0 THEN 'Low Score' ELSE 'Medium Score' END AS ScoreCategory
FROM UserActivity ua
INNER JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId
LEFT JOIN RankedPostEdits rpe ON pe.PostId = rpe.PostId AND rpe.rn = 1
WHERE pe.PostScore > 5 OR pe.UpVotesOnPost > 10
UNION ALL
SELECT
    'Community User' AS UserDisplayName,
    MAX(u.Reputation) AS Reputation,
    MIN(u.CreationDate) AS UserCreationDate,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
    pe.Title AS PostTitle,
    pe.PostCreationDate,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCount AS PostCommentCount,
    pe.FavoriteCount AS PostFavoriteCount,
    pe.CloseReason,
    pe.CommentCountOnPost,
    pe.UpVotesOnPost,
    pe.DownVotesOnPost,
    pe.DuplicateStatus,
    MAX(rpe.CreationDate) AS LastEditDate,
    CASE WHEN MAX(u.LastAccessDate) > pe.PostCreationDate THEN 'Older Post' ELSE 'Newer Post' END AS PostAgeRelative,
    LENGTH(pe.Title) AS TitleLength,
    UPPER(SUBSTRING(pe.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE WHEN pe.PostScore > 100 THEN 'High Score' WHEN pe.PostScore < 0 THEN 'Low Score' ELSE 'Medium Score' END AS ScoreCategory
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN PostEngagement pe ON p.Id = pe.PostId
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.OwnerUserId IS NULL OR p.OwnerUserId = -1 -- Community owned posts
GROUP BY pe.PostId, pe.Title, pe.PostCreationDate, pe.PostScore, pe.PostViewCount, pe.AnswerCount, pe.CommentCount, pe.FavoriteCount, pe.CloseReason, pe.CommentCountOnPost, pe.UpVotesOnPost, pe.DownVotesOnPost, pe.DuplicateStatus
HAVING COUNT(DISTINCT p.Id) > 50
ORDER BY Reputation DESC, PostScore DESC;
