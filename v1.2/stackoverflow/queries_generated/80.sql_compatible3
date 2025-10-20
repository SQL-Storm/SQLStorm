WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON NOT (t2.Id = ANY (r.Path))
    WHERE t2.IsRequired = TRUE AND t2.Count < r.Count
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerName,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnsweredByRegisteredUsers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        COUNT(*) OVER (
            PARTITION BY u.Id
            ORDER BY EXTRACT(EPOCH FROM p.CreationDate)
            RANGE BETWEEN 2592000 PRECEDING AND CURRENT ROW
        ) AS PostsLast30Days,
        SUM(p.Score) OVER (
            PARTITION BY u.Id
            ORDER BY EXTRACT(EPOCH FROM p.CreationDate)
            RANGE BETWEEN 2592000 PRECEDING AND CURRENT ROW
        ) AS ScoreLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
UserTopTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
UserTopTagRanks AS (
    SELECT
        ut.UserId,
        ut.Tag,
        ut.TagCount,
        RANK() OVER (PARTITION BY ut.UserId ORDER BY ut.TagCount DESC) AS TagRank
    FROM UserTopTags ut
),
UserTop3Tags AS (
    SELECT
        UserId,
        string_agg(Tag, ', ' ORDER BY TagCount DESC) AS TopTags
    FROM UserTopTagRanks
    WHERE TagRank <= 3
    GROUP BY UserId
)
SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.OwnerUserId,
    ur.DisplayName AS OwnerName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.ReputationRank,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(ans.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(ans.AnsweredByRegisteredUsers, 0) AS AnsweredByRegisteredUsers,
    tq.FavoriteCount,
    tq.ClosedDate,
    qcr.CloseReasonName,
    ua.PostsLast30Days,
    ua.ScoreLast30Days,
    ut3.TopTags,
    CASE
        WHEN tq.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN tq.Score > 100 AND tq.ViewCount > 10000 THEN 'Hot'
        ELSE 'Normal'
    END AS QuestionStatus,
    length(tq.Title) AS TitleLength,
    (strpos(lower(tq.Title), 'sql') > 0) AS TitleContainsSQL,
    COALESCE(tq.Tags, '') AS Tags,
    CASE WHEN tq.Tags IS NULL THEN 0 ELSE array_length(string_to_array(substring(tq.Tags FROM 2 FOR char_length(tq.Tags) - 2), '><'), 1) END AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY ur.UserId ORDER BY tq.Score DESC) AS UserQuestionRank
FROM TopQuestions tq
LEFT JOIN UserReputationStats ur ON ur.UserId = tq.OwnerUserId
LEFT JOIN AnswerStats ans ON ans.QuestionId = tq.Id
LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
LEFT JOIN UserActivityWindow ua ON ua.UserId = tq.OwnerUserId AND ua.PostId = tq.Id
LEFT JOIN UserTop3Tags ut3 ON ut3.UserId = tq.OwnerUserId
WHERE (tq.Score > 50 OR tq.ViewCount > 5000)
  AND (ur.GoldBadges + ur.SilverBadges + ur.BronzeBadges) > 0
  AND (ua.PostsLast30Days IS NULL OR ua.PostsLast30Days > 0)
ORDER BY tq.Score DESC, tq.ViewCount DESC
LIMIT 100;