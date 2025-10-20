-- {"query": "27044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1209} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.CreationDate AS UserCreationDate,
        COALESCE(u.LastAccessDate, u.CreationDate) AS LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.LastAccessDate
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.OwnerUserId, p.Title, p.Tags
),
ActiveUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.LastAccessDate,
        DENSE_RANK() OVER (ORDER BY ua.TotalPosts DESC, ua.TotalScore DESC) AS UserRank,
        LAG(ua.UserId) OVER (ORDER BY ua.TotalPosts DESC, ua.TotalScore DESC) AS PreviousUser,
        LEAD(ua.UserId) OVER (ORDER BY ua.TotalPosts DESC, ua.TotalScore DESC) AS NextUser
    FROM
        UserActivity ua
)
SELECT
    au.UserId,
    au.DisplayName,
    au.LastAccessDate,
    au.UserRank,
    au.PreviousUser,
    au.NextUser,
    pm.PostId,
    pm.PostTypeId,
    pm.CreationDate,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.TotalVotes,
    pm.UpVotes,
    pm.DownVotes,
    pm.LastVoteDate,
    pm.Title,
    (SELECT COUNT(*)
      FROM PostHistory ph
      WHERE ph.PostId = pm.PostId
        AND ph.PostHistoryTypeId IN (2, 5, 25)) AS EditCount,
    CASE
        WHEN pm.PostTypeId = 1 THEN 'Question'
        WHEN pm.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeName,
    COALESCE(ba.Name, 'No Badges') AS LatestBadge,
    ca.CommentCount AS TotalComments,
    ca.CommentCount / NULLIF(pm.ViewCount, 0) AS CommentRate
FROM
    ActiveUsers au
LEFT JOIN
    PostMetrics pm ON au.UserId = pm.OwnerUserId
LEFT JOIN
    (SELECT b.UserId, b.Name, ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
     FROM Badges b) ba ON au.UserId = ba.UserId AND ba.rn = 1
LEFT JOIN
    (SELECT p.OwnerUserId, COUNT(c.Id) AS CommentCount
     FROM Posts p
     JOIN Comments c ON p.Id = c.PostId
     GROUP BY p.OwnerUserId) ca ON au.UserId = ca.OwnerUserId
WHERE
    au.UserRank <= 100
    AND (pm.PostTypeId = 1 OR pm.PostTypeId IS NULL)
ORDER BY
    au.UserRank, pm.CreationDate DESC;
