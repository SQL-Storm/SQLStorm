WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
LatestEdits AS (
    SELECT
        rpe.PostId,
        rpe.UserId AS LastEditorUserId,
        rpe.UserDisplayName AS LastEditorDisplayName,
        rpe.EditDate AS LastEditDate,
        rpe.EditComment AS LastEditComment
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVoteCount,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS FavoriteCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.AnswerCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS recent_rank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
)
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COALESCE(upa.TotalPostsOwned, 0) AS TotalPostsOwned,
    COALESCE(upa.QuestionCount, 0) AS QuestionsPosted,
    COALESCE(upa.AnswerCount, 0) AS AnswersPosted,
    COALESCE(uvs.UpVoteCount, 0) AS TotalUpVotesReceived,
    COALESCE(uvs.DownVoteCount, 0) AS TotalDownVotesReceived,
    COALESCE(uvs.FavoriteCount, 0) AS TotalFavoritesReceived,
    le.LastEditDate,
    le.LastEditorDisplayName,
    le.LastEditComment,
    CASE
        WHEN upa.AvgPostScore > 50 THEN 'High Performer'
        WHEN upa.AvgPostScore BETWEEN 10 AND 50 THEN 'Average Contributor'
        ELSE 'Novice Contributor'
    END AS PerformanceTier,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Legend%') THEN 'Has Legendary Badge'
        ELSE 'No Legendary Badge'
    END AS BadgeStatus,
    rq.Title AS MostRecentQuestionTitle,
    CAST((EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate))) / 86400 AS INTEGER) AS AccountAgeDays,
    CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        WHEN POSITION('stackoverflow.com' IN u.WebsiteUrl) > 0 THEN 'Stack Overflow Site'
        ELSE 'External Website'
    END AS WebsiteCategory
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN LatestEdits le ON u.Id = le.PostId
LEFT JOIN RecentQuestions rq ON u.Id = rq.OwnerUserId AND rq.recent_rank = 1
WHERE u.Id <= 10000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    upa.TotalPostsOwned,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AvgPostScore,
    uvs.UpVoteCount,
    uvs.DownVoteCount,
    uvs.FavoriteCount,
    le.LastEditDate,
    le.LastEditorDisplayName,
    le.LastEditComment,
    rq.Title,
    u.CreationDate,
    u.WebsiteUrl
ORDER BY u.Reputation DESC, u.Id;