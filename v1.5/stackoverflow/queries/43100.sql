WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.Score) AS HighestPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        COUNT(DISTINCT ph.Id) AS TotalEdits
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE u.LastAccessDate > DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        HighestPostScore,
        TotalViewCount,
        TotalEdits,
        RANK() OVER (ORDER BY TotalPosts DESC, TotalEdits DESC) AS UserRank
    FROM UserActivity
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) / 3600) AS AvgHoursToFirstEdit
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            MIN(CreationDate) AS CreationDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate > DATE '2024-10-01' - INTERVAL '6 months'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
)
SELECT 
    tc.DisplayName,
    tc.TotalQuestions,
    tc.TotalAnswers,
    tc.HighestPostScore,
    pm.Title,
    pm.Score,
    pm.ViewCount,
    pm.TotalVotes,
    pm.UpVotes,
    pm.DownVotes,
    pm.AvgHoursToFirstEdit
FROM TopContributors tc
JOIN Posts p ON tc.UserId = p.OwnerUserId
JOIN PostMetrics pm ON p.Id = pm.PostId
WHERE tc.UserRank <= 10
ORDER BY tc.TotalPosts DESC, pm.Score DESC;