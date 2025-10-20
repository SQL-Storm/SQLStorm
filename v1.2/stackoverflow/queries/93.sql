WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
      AND t.IsRequired = FALSE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        CAST(r.Path || ' > ' || t2.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t2
    JOIN RecursiveTagHierarchy r
      ON t2.Id <> r.Id
     AND t2.Count < r.Count
    WHERE t2.IsModeratorOnly = FALSE
      AND t2.IsRequired = FALSE
      AND r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COALESCE(SUM(b.Class), 0) AS BadgeScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
      AND p.Score > 0
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Score > 10 THEN 1 ELSE 0 END) AS HighScoreAnswers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
PostCloseReasons AS (
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
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        SUM(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS ScoreLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
UserTopTags AS (
    SELECT
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    GROUP BY u.Id, Tag
),
UserTopTagRanks AS (
    SELECT
        ut.UserId,
        ut.Tag,
        ut.TagCount,
        RANK() OVER (PARTITION BY ut.UserId ORDER BY ut.TagCount DESC) AS TagRank
    FROM UserTopTags ut
),
FinalUserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        COALESCE(MAX(CASE WHEN ptr.TagRank = 1 THEN ptr.Tag END), 'No Tags') AS TopTag,
        COALESCE(MAX(ptr.TagCount), 0) AS TopTagCount
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN UserActivityWindow ua ON ua.UserId = u.Id
    LEFT JOIN UserTopTagRanks ptr ON ptr.UserId = u.Id AND ptr.TagRank = 1
    GROUP BY u.Id, u.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ua.PostsLast30Days, ua.ScoreLast30Days
)
SELECT
    f.DisplayName,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.PostsLast30Days,
    f.ScoreLast30Days,
    f.TopTag,
    f.TopTagCount,
    COALESCE(pas.AnswerCount, 0) AS TotalAnswersForTopQuestions,
    COALESCE(pas.MaxAnswerScore, 0) AS MaxAnswerScoreForTopQuestions,
    COALESCE(CAST(pas.AvgAnswerScore AS NUMERIC(10,2)), 0) AS AvgAnswerScoreForTopQuestions,
    COALESCE(pcr.CloseReasonName, 'Not Closed') AS LastCloseReason,
    pcr.CloseDate,
    rh.Level AS TagHierarchyLevel,
    rh.Path AS TagHierarchyPath
FROM FinalUserStats f
LEFT JOIN TopPosts tp ON tp.OwnerUserId = f.Id AND tp.rn = 1 AND tp.PostTypeId = 1
LEFT JOIN PostAnswerStats pas ON pas.QuestionId = tp.Id
LEFT JOIN PostCloseReasons pcr ON pcr.PostId = tp.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = f.TopTag
WHERE f.PostsLast30Days > 0
ORDER BY f.ScoreLast30Days DESC, f.GoldBadges DESC, f.DisplayName
FETCH FIRST 100 ROWS ONLY;