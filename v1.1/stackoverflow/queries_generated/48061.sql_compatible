WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.ParentId,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
),
UserAvgScore AS (
    SELECT
        OwnerUserId,
        AVG(CAST(Score AS NUMERIC)) AS AverageScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND Score IS NOT NULL AND PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
),
UserRecentActivity AS (
    SELECT
        OwnerUserId,
        MAX(LastActivityDate) AS LastActivity
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT
    rp_q.Id AS QuestionId,
    rp_q.Score AS QuestionScore,
    rp_q.AnswerCount AS QuestionAnswerCount,
    rp_q.CommentCount AS QuestionCommentCount,
    rp_a.Id AS AnswerId,
    rp_a.Score AS AnswerScore,
    upc.TotalPosts AS UserTotalPosts,
    uas.AverageScore AS UserAverageScore,
    ura.LastActivity AS UserLastActivity,
    rp_q.CreationDate
FROM RankedPosts rp_q
LEFT JOIN RankedPosts rp_a
  ON rp_q.Id = rp_a.ParentId
  AND rp_a.PostTypeId = 2
  AND rp_a.rn = 1
LEFT JOIN UserPostCounts upc
  ON rp_q.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserAvgScore uas
  ON rp_q.OwnerUserId = uas.OwnerUserId
LEFT JOIN UserRecentActivity ura
  ON rp_q.OwnerUserId = ura.OwnerUserId
WHERE rp_q.PostTypeId = 1
  AND rp_q.rn <= 1000
GROUP BY
    rp_q.Id,
    rp_q.Score,
    rp_q.AnswerCount,
    rp_q.CommentCount,
    rp_a.Id,
    rp_a.Score,
    upc.TotalPosts,
    uas.AverageScore,
    ura.LastActivity,
    rp_q.CreationDate
ORDER BY rp_q.CreationDate DESC
LIMIT 500;