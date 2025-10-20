WITH RecursiveCTE AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    COALESCE(u.DisplayName, '') || '_' || SUBSTRING(CAST(ROW_NUMBER() OVER (ORDER BY u.Reputation) AS VARCHAR(5)), 1, 5) AS SurvivorSlug
  FROM Users u
  LEFT JOIN Badges b
    ON u.Id = b.UserId
    AND b.TagBased = FALSE
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
PopularQuestionAnswers AS (
  SELECT
    CAST(NULL AS BIGINT) AS QuestionId,
    CAST(NULL AS BIGINT) AS AnswerId,
    CAST(NULL AS BIGINT) AS OwnerUserId,
    CAST(NULL AS TIMESTAMP) AS CreationDate
  WHERE FALSE
)
SELECT
  r.UserId,
  r.BadgeCount,
  r.GoldBadges,
  r.SurvivorSlug
FROM RecursiveCTE r
GROUP BY r.UserId, r.BadgeCount, r.GoldBadges, r.SurvivorSlug;