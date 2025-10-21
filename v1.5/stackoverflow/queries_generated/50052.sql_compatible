WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        COALESCE(p_stats.QuestionCount, 0) AS QuestionCount,
        COALESCE(p_stats.AnswerCount, 0) AS AnswerCount,
        COALESCE(p_stats.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(p_stats.LastActivityDate, u.CreationDate) AS LastActivityDate,
        COALESCE(c_stats.CommentCount, 0) AS CommentCount,
        COALESCE(v_stats.UpvotesGiven, 0) AS UpvotesGiven,
        COALESCE(b_stats.GoldBadges, 0) AS GoldBadges,
        COALESCE(b_stats.SilverBadges, 0) AS SilverBadges
    FROM Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
            SUM(Score) AS TotalPostScore,
            MAX(LastActivityDate) AS LastActivityDate
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p_stats ON u.Id = p_stats.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount FROM Comments WHERE UserId IS NOT NULL GROUP BY UserId
    ) c_stats ON u.Id = c_stats.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS UpvotesGiven FROM Votes WHERE UserId IS NOT NULL AND VoteTypeId = 2 GROUP BY UserId
    ) v_stats ON u.Id = v_stats.UserId
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
        FROM Badges
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) b_stats ON u.Id = b_stats.UserId
    WHERE u.Reputation > 50000 AND u.UpVotes > u.DownVotes
),
RankedAnswers AS (
    SELECT
        Id AS AnswerId,
        OwnerUserId,
        Score,
        CreationDate,
        ParentId AS QuestionId,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, FavoriteCount DESC, ViewCount DESC) AS rn
    FROM Posts
    WHERE PostTypeId = 2
      AND OwnerUserId IN (SELECT UserId FROM UserMetrics WHERE AnswerCount > 10)
),
TopAnswerAnalysis AS (
    SELECT
        ra.OwnerUserId,
        ra.AnswerId,
        ra.Score AS TopAnswerScore,
        ra.QuestionId,
        COUNT(ph.Id) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstInteractionDate,
        (EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))) / 3600.0) AS EditTimeSpanHours
    FROM RankedAnswers ra
    JOIN PostHistory ph ON ra.AnswerId = ph.PostId
    WHERE ra.rn = 1
    GROUP BY ra.OwnerUserId, ra.AnswerId, ra.Score, ra.QuestionId
),
QuestionContext AS (
    SELECT
        taa.OwnerUserId,
        p.Title AS QuestionTitle,
        p.Tags AS QuestionTags,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.CommentCount AS QuestionCommentCount,
        p.FavoriteCount AS QuestionFavoriteCount
    FROM Posts p
    JOIN TopAnswerAnalysis taa ON p.Id = taa.QuestionId
)
SELECT
    um.DisplayName,
    um.Reputation,
    um.AnswerCount,
    um.QuestionCount,
    um.GoldBadges,
    um.SilverBadges,
    um.CommentCount,
    um.UpvotesGiven,
    ROUND(CAST(um.AnswerCount AS DECIMAL) / NULLIF(CAST(um.QuestionCount AS DECIMAL), 0), 2) AS AnswerToQuestionRatio,
    taa.TopAnswerScore,
    taa.EditCount AS TopAnswerEdits,
    taa.DistinctEditors AS TopAnswerEditors,
    ROUND(taa.EditTimeSpanHours, 2) AS TopAnswerEditSpanHours,
    qc.QuestionTitle,
    qc.QuestionTags,
    qc.QuestionViewCount,
    DENSE_RANK() OVER (
        ORDER BY
            (um.Reputation * 0.3) +
            (um.TotalPostScore * 0.25) +
            (taa.TopAnswerScore * 0.2) +
            (um.UpvotesGiven * 0.1) +
            (um.GoldBadges * 100) +
            (um.AnswerCount * 0.15) DESC
    ) AS PowerUserRank
FROM UserMetrics um
JOIN TopAnswerAnalysis taa ON um.UserId = taa.OwnerUserId
JOIN QuestionContext qc ON um.UserId = qc.OwnerUserId
WHERE um.GoldBadges >= 5
  AND um.AnswerCount > (um.QuestionCount * 2)
  AND taa.EditTimeSpanHours > 0
ORDER BY PowerUserRank, um.Reputation DESC
LIMIT 100;