WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 15000 AND IsModeratorOnly = '0'
),
UserAnswerStats AS (
    SELECT
        p_ans.OwnerUserId,
        COUNT(p_ans.Id) AS TotalAnswers,
        AVG(p_ans.Score) AS AvgAnswerScore,
        SUM(p_ans.CommentCount) AS TotalCommentsOnAnswers,
        MAX(p_ans.CreationDate) AS LastAnswerDate
    FROM Posts p_ans
    JOIN Posts p_q ON p_ans.ParentId = p_q.Id
    WHERE p_ans.PostTypeId = 2
      AND p_ans.OwnerUserId IS NOT NULL
      AND p_ans.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 year')
      AND EXISTS (
          SELECT 1
          FROM PopularTags pt
          WHERE p_q.Tags LIKE '%' || pt.TagName || '%'
      )
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(p_ans.Id) > 25
),
UserBadgeStats AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT
        UserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
        COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
    HAVING COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) > 1000
),
RankedPowerUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        uas.TotalAnswers,
        uas.AvgAnswerScore,
        uas.LastAnswerDate,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        uvs.UpvotesGiven,
        (
            (LOG(u.Reputation) * 0.4) +
            (uas.AvgAnswerScore * 0.2) +
            (LOG(uas.TotalAnswers + 1) * 0.2) +
            (COALESCE(ubs.GoldBadges, 0) * 1.5) +
            (COALESCE(ubs.SilverBadges, 0) * 0.7)
        ) AS PowerScore,
        FIRST_VALUE(p.Id) OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.CreationDate DESC) AS TopAnswerId
    FROM Users u
    JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
    JOIN UserVoteStats uvs ON u.Id = uvs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 2
    WHERE u.Reputation > 50000
)
SELECT
    DENSE_RANK() OVER (ORDER BY rpu.PowerScore DESC) AS Rank,
    rpu.DisplayName,
    rpu.Reputation,
    rpu.TotalAnswers AS AnswersInPopularTags,
    CAST(rpu.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgScore,
    rpu.GoldBadges,
    rpu.SilverBadges,
    rpu.UpvotesGiven,
    CAST(rpu.PowerScore AS DECIMAL(10, 2)) AS PowerScore,
    (
        SELECT Title
        FROM Posts
        WHERE Id = (
            SELECT ParentId
            FROM Posts
            WHERE Id = rpu.TopAnswerId
        )
    ) AS TopAnswerQuestionTitle,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.UserId = rpu.UserId AND ph.PostHistoryTypeId = 2
    ) AS LastPostCreationDate
FROM RankedPowerUsers rpu
GROUP BY
    rpu.UserId,
    rpu.DisplayName,
    rpu.Reputation,
    rpu.TotalAnswers,
    rpu.AvgAnswerScore,
    rpu.GoldBadges,
    rpu.SilverBadges,
    rpu.UpvotesGiven,
    rpu.PowerScore,
    rpu.TopAnswerId
ORDER BY Rank, rpu.Reputation DESC
LIMIT 100;