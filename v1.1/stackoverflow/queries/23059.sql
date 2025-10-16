WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(b.Id) > 5
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.OwnerUserId,
        NULLIF(
          TRIM(BOTH '|' FROM REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><', '|'), ' ', '')),
          ''
        ) AS TagList,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 10000
),
CorrelatedAnswers AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId,
        p.Score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE p.PostTypeId = 2
),
ComplexJoin AS (
    SELECT 
        tq.PostId,
        tq.Title,
        tq.ViewCount,
        tq.OwnerUserId,
        ubs.DisplayName,
        ubs.BadgeCount,
        ubs.GoldBadges,
        ubs.SilverBadges,
        COALESCE(ubs.LatestBadgeDate, NULL) AS EffectiveBadgeDate,
        tq.TagList,
        ca.AnswerId,
        ca.Score AS AnswerScore,
        ca.PositiveComments,
        RANK() OVER (ORDER BY tq.ViewCount DESC) AS GlobalRank,
        (ubs.DisplayName || ' - ' || tq.Title) AS UserPostString
    FROM TopQuestions tq
    INNER JOIN UserBadgeStats ubs ON tq.OwnerUserId = ubs.UserId
    LEFT JOIN CorrelatedAnswers ca ON tq.PostId = ca.ParentId
    WHERE (tq.TagList IS NOT NULL AND POSITION('sql' IN tq.TagList) > 0)
      AND (ubs.GoldBadges > 0 OR ubs.SilverBadges > 3)
      AND tq.QuestionRank = 1
    GROUP BY
        tq.PostId,
        tq.Title,
        tq.ViewCount,
        tq.OwnerUserId,
        ubs.DisplayName,
        ubs.BadgeCount,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.LatestBadgeDate,
        tq.TagList,
        ca.AnswerId,
        ca.Score,
        ca.PositiveComments
)
SELECT * FROM ComplexJoin
UNION ALL
SELECT 
    CAST(NULL AS INTEGER) AS PostId,
    'Summary' AS Title,
    SUM(ViewCount) AS ViewCount,
    CAST(NULL AS INTEGER) AS OwnerUserId,
    'Total' AS DisplayName,
    SUM(BadgeCount) AS BadgeCount,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    MAX(EffectiveBadgeDate) AS EffectiveBadgeDate,
    CAST(NULL AS VARCHAR) AS TagList,
    CAST(NULL AS INTEGER) AS AnswerId,
    SUM(AnswerScore) AS AnswerScore,
    SUM(PositiveComments) AS PositiveComments,
    CAST(NULL AS INTEGER) AS GlobalRank,
    'Aggregate Stats' AS UserPostString
FROM ComplexJoin;