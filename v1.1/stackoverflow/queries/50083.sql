WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND p.OwnerUserId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 10
),
UserEngagement AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven,
        SUM(v.BountyAmount) AS TotalBountyGiven,
        COUNT(c.Id) AS CommentsMade,
        AVG(c.Score) AS AvgCommentScore
    FROM Votes v
    LEFT JOIN Comments c ON v.UserId = c.UserId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserTopTag AS (
    SELECT
        p.OwnerUserId,
        (
          SELECT tt.TagName
          FROM (
            SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><') AS TagName
          ) extracted
          JOIN (
            SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><') AS TagName
          ) tt ON tt.TagName = extracted.TagName
          GROUP BY tt.TagName
          ORDER BY COUNT(*) DESC
          LIMIT 1
        ) AS PrimaryTag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.Tags
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ue.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(ue.CommentsMade, 0) AS CommentsMade,
    utt.PrimaryTag,
    uas.AverageScore,
    uas.TotalViews,
    EXTRACT(EPOCH FROM (uas.LastPostActivityDate - uas.FirstPostDate)) / 86400.0 AS ActiveDays,
    (uas.AnswerCount * 10 + uas.QuestionCount * 5 + uas.TotalScore) /
      (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - uas.UserCreationDate)) / 86400.0 + 1) AS EngagementScore,
    RANK() OVER (PARTITION BY utt.PrimaryTag ORDER BY uas.Reputation DESC) AS RankInPrimaryTag
FROM UserActivitySummary uas
JOIN UserEngagement ue ON uas.UserId = ue.UserId
JOIN UserBadges ub ON uas.UserId = ub.UserId
LEFT JOIN UserTopTag utt ON uas.UserId = utt.OwnerUserId
WHERE
    uas.AnswerCount > uas.QuestionCount
    AND uas.LastPostActivityDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '3 year'
    AND COALESCE(ub.GoldBadges, 0) > (
        SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY b.c)
        FROM (SELECT COUNT(*) AS c FROM Badges WHERE Class = 1 GROUP BY UserId) b
    )
    AND utt.PrimaryTag IS NOT NULL
ORDER BY
    EngagementScore DESC,
    uas.Reputation DESC
LIMIT 200;