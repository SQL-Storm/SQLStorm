WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditType,
        LAG(ph.Text, 1, 'N/A') OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS PreviousText,
        ph.Text AS CurrentText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 7, 8)
      AND ph.Text IS NOT NULL
      AND ph.Text <> ''
),
PostEditDiffs AS (
    SELECT
        rpe.PostId,
        rpe.UserId,
        rpe.EditorDisplayName,
        rpe.EditDate,
        rpe.EditType,
        CASE
            WHEN rpe.EditType LIKE '%Title%' THEN LENGTH(rpe.CurrentText) - LENGTH(REPLACE(rpe.CurrentText, ' ', ''))
            WHEN rpe.EditType LIKE '%Body%' THEN LENGTH(rpe.CurrentText) - LENGTH(REPLACE(rpe.CurrentText, ' ', ''))
            ELSE 0
        END AS WordCountDiff,
        CASE
            WHEN rpe.EditType LIKE '%Title%' THEN LENGTH(rpe.CurrentText)
            WHEN rpe.EditType LIKE '%Body%' THEN LENGTH(rpe.CurrentText)
            ELSE 0
        END AS CharacterCount,
        CASE
            WHEN rpe.EditType LIKE '%Rollback%' THEN 1
            ELSE 0
        END AS IsRollback,
        rpe.rn
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAnswered,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
PostScores AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.CommentCount, p.FavoriteCount
)
SELECT
    ps.PostId,
    ps.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ps.Score,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.Upvotes,
    ps.Downvotes,
    ROUND(
      CASE WHEN (ps.Upvotes + ps.Downvotes) = 0 THEN NULL
           ELSE CAST(ps.Upvotes AS NUMERIC) / CAST((ps.Upvotes + ps.Downvotes) AS NUMERIC)
      END
    , 3) AS UpvoteRatio,
    CASE
        WHEN ps.Score > 100 THEN 'HighScore'
        WHEN ps.Score BETWEEN 10 AND 100 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS ScoreCategory,
    ped.EditorDisplayName AS LatestEditor,
    ped.EditDate AS LatestEditDate,
    ped.EditType AS LatestEditType,
    ped.WordCountDiff AS LatestWordCountDiff,
    ped.CharacterCount AS LatestCharCount,
    ped.IsRollback AS WasLatestEditRollback,
    ua.QuestionsAnswered,
    ua.CommentsMade,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.MaxReputation
FROM PostScores ps
JOIN Users u ON ps.OwnerUserId = u.Id
LEFT JOIN PostEditDiffs ped ON ps.PostId = ped.PostId AND ped.rn = 1
LEFT JOIN UserActivity ua ON ps.OwnerUserId = ua.UserId
WHERE u.Id <> -1
  AND ps.Score > 0
GROUP BY
    ps.PostId,
    ps.OwnerUserId,
    u.DisplayName,
    ps.Score,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.Upvotes,
    ps.Downvotes,
    ped.EditorDisplayName,
    ped.EditDate,
    ped.EditType,
    ped.WordCountDiff,
    ped.CharacterCount,
    ped.IsRollback,
    ua.QuestionsAnswered,
    ua.CommentsMade,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.MaxReputation
ORDER BY ps.Score DESC, ps.FavoriteCount DESC
LIMIT 1000;