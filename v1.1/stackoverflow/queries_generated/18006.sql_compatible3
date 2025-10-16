WITH RelevantPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS ActualCommentCount,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_post_type_date,
        DENSE_RANK() OVER(ORDER BY p.Score DESC) AS rank_by_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL AND p.Score > 0
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AverageCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score) AS TotalScoreFromPosts,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
),
RecentEdits AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
),
TopUsersByReputation AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE Reputation > 10000
),
_anchor_ts AS (
    SELECT CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS ref_ts
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount AS AnswerCountFromPostTable,
    COALESCE(pc.CommentCountForPost, 0) AS ActualCommentCountFromCommentsTable,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    COALESCE(ua.QuestionsAsked, 0) AS UserQuestionsAsked,
    COALESCE(ua.AnswersGiven, 0) AS UserAnswersGiven,
    COALESCE(ua.TotalScoreFromPosts, 0) AS UserTotalScoreFromPosts,
    COALESCE(re.EditCount, 0) AS PostEditCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE WHEN rp.OwnerReputation > 50000 THEN 'High Reputation User' WHEN rp.OwnerReputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation User' ELSE 'Lower Reputation User' END AS UserReputationTier,
    (rp.PostTypeName || ' - ' || COALESCE(rp.OwnerDisplayName, 'Community')) AS PostIdentifier,
    CAST((EXTRACT(EPOCH FROM (a.ref_ts - rp.PostCreationDate)) / 86400) AS INTEGER) AS DaysSinceCreation,
    rp.rank_by_score,
    tur.DisplayName AS TopUserDisplayName,
    tur.ReputationRank
FROM RelevantPosts rp
LEFT JOIN PostComments pc ON rp.PostId = pc.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN RecentEdits re ON rp.PostId = re.PostId
LEFT JOIN TopUsersByReputation tur ON rp.OwnerUserId = tur.Id OR tur.ReputationRank = 1
JOIN _anchor_ts a ON 1=1
WHERE rp.PostScore > 10
  AND rp.PostCreationDate BETWEEN (a.ref_ts - INTERVAL '12' MONTH) AND a.ref_ts
  AND (rp.AnswerCount IS NULL OR rp.AnswerCount > 0)
  AND (rp.PostId % 7 = 0)
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount AS AnswerCountFromPostTable,
    COALESCE(pc.CommentCountForPost, 0) AS ActualCommentCountFromCommentsTable,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    COALESCE(ua.QuestionsAsked, 0) AS UserQuestionsAsked,
    COALESCE(ua.AnswersGiven, 0) AS UserAnswersGiven,
    COALESCE(ua.TotalScoreFromPosts, 0) AS UserTotalScoreFromPosts,
    COALESCE(re.EditCount, 0) AS PostEditCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE WHEN rp.OwnerReputation > 50000 THEN 'High Reputation User' WHEN rp.OwnerReputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation User' ELSE 'Lower Reputation User' END AS UserReputationTier,
    (rp.PostTypeName || ' - ' || COALESCE(rp.OwnerDisplayName, 'Community')) AS PostIdentifier,
    CAST((EXTRACT(EPOCH FROM (a.ref_ts - rp.PostCreationDate)) / 86400) AS INTEGER) AS DaysSinceCreation,
    rp.rank_by_score,
    tur.DisplayName AS TopUserDisplayName,
    tur.ReputationRank
FROM RelevantPosts rp
LEFT JOIN PostComments pc ON rp.PostId = pc.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN RecentEdits re ON rp.PostId = re.PostId
LEFT JOIN TopUsersByReputation tur ON rp.OwnerUserId = tur.Id OR tur.ReputationRank = 1
JOIN _anchor_ts a ON 1=1
WHERE rp.PostScore <= 10
  AND rp.PostCreationDate < (a.ref_ts - INTERVAL '12' MONTH)
  AND rp.OwnerReputation < 1000
  AND rp.PostId IN (SELECT ph.PostId FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10)
ORDER BY PostCreationDate DESC, PostScore DESC
LIMIT 1000;