WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
LatestPostEdits AS (
    SELECT
        PostId,
        PostHistoryTypeId,
        EditDate,
        EditorDisplayName
    FROM RankedPostEdits
    WHERE rn = 1
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        u_owner.DisplayName AS OwnerDisplayName,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COALESCE(p.ClosedDate, p.LastActivityDate) AS EffectiveEndDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS TotalAnswerScore,
        MAX(CreationDate) AS LastPostCreationDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
AggregatedVotes AS (
    SELECT
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotes,
        COUNT(CASE WHEN VoteTypeId = 5 THEN 1 ELSE NULL END) AS FavoriteVotes
    FROM Votes
    GROUP BY PostId
)
SELECT
    pd.PostId,
    pd.PostType,
    pd.Title,
    pd.PostCreationDate,
    pd.OwnerDisplayName,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.PostStatus,
    pd.EffectiveEndDate,
    COALESCE(lpe_title.EditDate, TIMESTAMP '1900-01-01 00:00:00') AS LastTitleEditDate,
    COALESCE(lpe_body.EditDate, TIMESTAMP '1900-01-01 00:00:00') AS LastBodyEditDate,
    COALESCE(lpe_tags.EditDate, TIMESTAMP '1900-01-01 00:00:00') AS LastTagsEditDate,
    COALESCE(av.UpVotes, 0) AS TotalUpVotes,
    COALESCE(av.DownVotes, 0) AS TotalDownVotes,
    COALESCE(av.FavoriteVotes, 0) AS TotalFavoriteVotes,
    ua.QuestionCount,
    ua.AnswerCount AS UserAnswerCount,
    ua.TotalQuestionScore,
    ua.TotalAnswerScore,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pd.PostCreationDate)) / 86400 AS INTEGER) AS PostAgeDays,
    CASE
        WHEN pd.Score > 1000 AND pd.ViewCount > 10000 THEN 'Popular'
        WHEN pd.Score < 0 AND pd.AnswerCount = 0 THEN 'Unpopular_Unanswered'
        WHEN pd.FavoriteCount > (pd.AnswerCount + pd.CommentCount) THEN 'Highly_Faved'
        ELSE 'Standard'
    END AS PostCategorization,
    UPPER(SUBSTRING(pd.Title FROM 1 FOR 3)) AS TitlePrefix,
    SUBSTRING(pd.Tags FROM 3 FOR (POSITION('>' IN pd.Tags) - 3)) AS FirstTag
FROM PostDetails pd
LEFT JOIN LatestPostEdits lpe_title ON pd.PostId = lpe_title.PostId AND lpe_title.PostHistoryTypeId = 4
LEFT JOIN LatestPostEdits lpe_body ON pd.PostId = lpe_body.PostId AND lpe_body.PostHistoryTypeId = 5
LEFT JOIN LatestPostEdits lpe_tags ON pd.PostId = lpe_tags.PostId AND lpe_tags.PostHistoryTypeId = 6
LEFT JOIN AggregatedVotes av ON pd.PostId = av.PostId
LEFT JOIN UserActivity ua ON pd.OwnerUserId = ua.UserId
WHERE pd.PostCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5 years')
  AND ua.LastPostCreationDate IS NOT NULL
  AND pd.OwnerUserId <> -1
ORDER BY pd.PostCreationDate DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;