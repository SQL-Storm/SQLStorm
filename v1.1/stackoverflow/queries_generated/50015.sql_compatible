WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 10
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AveragePostScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
      AND u.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
AnswerQuality AS (
    SELECT
        a.OwnerUserId,
        COUNT(DISTINCT a.Id) AS AnswersInPopularTags,
        SUM(a.Score) AS ScoreFromPopularAnswers,
        AVG(CAST(q.ViewCount AS DOUBLE PRECISION)) AS AvgViewCountOfAnsweredQuestions,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswersInPopularTags,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) / 3600.0 AS AvgHoursToAnswer
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    JOIN PopularTags pt ON q.Tags LIKE '%' || '<' || pt.TagName || '>' || '%'
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),
RankedUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.TotalPosts,
        ua.TotalAnswers,
        ua.TotalPostScore,
        ua.TotalComments,
        ua.GoldBadges,
        ua.SilverBadges,
        COALESCE(aq.ScoreFromPopularAnswers, 0) AS ScoreFromPopularAnswers,
        COALESCE(aq.AcceptedAnswersInPopularTags, 0) AS AcceptedAnswersInPopularTags,
        COALESCE(aq.AvgViewCountOfAnsweredQuestions, 0) AS AvgViewCountOfAnsweredQuestions,
        (
            (ua.TotalPostScore * 0.2) +
            (ua.Reputation * 0.1) +
            (ua.GoldBadges * 100) +
            (ua.SilverBadges * 25) +
            (COALESCE(aq.ScoreFromPopularAnswers, 0) * 0.5) +
            (COALESCE(aq.AcceptedAnswersInPopularTags, 0) * 50) +
            (ua.TotalComments * 0.05)
        ) AS InfluenceScore,
        ROW_NUMBER() OVER (
            PARTITION BY EXTRACT(YEAR FROM ua.CreationDate)
            ORDER BY
                (ua.TotalPostScore * 0.2) +
                (ua.Reputation * 0.1) +
                (ua.GoldBadges * 100) +
                (ua.SilverBadges * 25) +
                (COALESCE(aq.ScoreFromPopularAnswers, 0) * 0.5) +
                (COALESCE(aq.AcceptedAnswersInPopularTags, 0) * 50) DESC
        ) AS RankInCreationYear
    FROM UserActivity ua
    LEFT JOIN AnswerQuality aq ON ua.UserId = aq.OwnerUserId
)
SELECT
    ru.DisplayName,
    ru.Reputation,
    ru.InfluenceScore,
    ru.RankInCreationYear,
    EXTRACT(YEAR FROM ru.CreationDate) AS CreationYear,
    ru.TotalPosts,
    ru.TotalAnswers,
    ru.TotalComments,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.ScoreFromPopularAnswers,
    ru.AcceptedAnswersInPopularTags,
    ph_summary.LastEditActivity,
    ph_summary.DistinctEditors
FROM RankedUsers ru
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        MAX(ph.CreationDate) AS LastEditActivity,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IN (SELECT UserId FROM RankedUsers)
      AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY p.OwnerUserId
) ph_summary ON ru.UserId = ph_summary.OwnerUserId
WHERE ru.InfluenceScore > 1000
ORDER BY ru.InfluenceScore DESC
LIMIT 100;