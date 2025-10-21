-- {"query": "48074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 609} 
WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits (Title, Body, Tags)
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
TopEditors AS (
    SELECT
        rph.UserId,
        COUNT(DISTINCT rph.PostId) AS EditedPostsCount,
        MAX(rph.CreationDate) AS LastEditDate
    FROM RankedPostHistory rph
    WHERE rph.rn = 1 -- Consider only the latest edit of each type per post
    GROUP BY rph.UserId
    ORDER BY EditedPostsCount DESC
    LIMIT 10
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.CommentsMade,
    upa.UpVotesGiven,
    upa.DownVotesGiven,
    upa.LastPostDate,
    upa.AvgPostScore,
    upa.ClosedPosts,
    te.EditedPostsCount,
    te.LastEditDate
FROM UserPostActivity upa
JOIN TopEditors te ON upa.UserId = te.UserId
ORDER BY upa.TotalPosts DESC, upa.Questions DESC, upa.Answers DESC
LIMIT 100;