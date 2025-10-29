-- {"query": "3800.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2355} 
WITH UserStats AS (
   SELECT u.Id,
          u.DisplayName,
          u.Reputation,
          COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
          COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
          COALESCE(SUM(p.Score),0) AS TotalScore,
          AVG(p.Score)::numeric(10,2) AS AvgScore,
          MAX(p.CreationDate) AS LastPostDate
   FROM Users u
   LEFT JOIN Posts p ON p.OwnerUserId = u.Id
   GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
   SELECT b.UserId,
          COUNT(*) AS BadgeCount,
          COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
          COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
          COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
   FROM Badges b
   GROUP BY b.UserId
),
RecentActivity AS (
   SELECT u.Id,
          (SELECT p.Title FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.CreationDate DESC LIMIT 1) AS LatestQuestionTitle,
          (SELECT p.CreationDate FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.CreationDate DESC LIMIT 1) AS LatestQuestionDate
   FROM Users u
),
TagUsage AS (
   SELECT u.Id AS UserId,
          t.TagName,
          COUNT(*) AS TagCount
   FROM Users u
   JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
   JOIN LATERAL (SELECT unnest(string_to_array(trim(both '<>' from p.Tags), '><')) AS Tag) AS pt ON true
   JOIN Tags t ON t.TagName = pt.Tag
   GROUP BY u.Id, t.TagName
),
RankedUsers AS (
   SELECT us.Id,
          us.DisplayName,
          us.Reputation,
          us.QuestionCount,
          us.AnswerCount,
          us.TotalScore,
          us.AvgScore,
          bs.BadgeCount,
          bs.GoldBadges,
          bs.SilverBadges,
          bs.BronzeBadges,
          ra.LatestQuestionTitle,
          ra.LatestQuestionDate,
          ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalScore DESC) AS RepScoreRank,
          RANK() OVER (ORDER BY (us.QuestionCount + us.AnswerCount) DESC) AS ActivityRank
   FROM UserStats us
   LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
   LEFT JOIN RecentActivity ra ON ra.Id = us.Id
)
SELECT
   ru.Id,
   ru.DisplayName,
   ru.Reputation,
   ru.QuestionCount,
   ru.AnswerCount,
   ru.TotalScore,
   ru.AvgScore,
   COALESCE(ru.BadgeCount,0) AS TotalBadges,
   COALESCE(ru.GoldBadges,0) AS GoldBadges,
   COALESCE(ru.SilverBadges,0) AS SilverBadges,
   COALESCE(ru.BronzeBadges,0) AS BronzeBadges,
   ru.RepScoreRank,
   ru.ActivityRank,
   CASE WHEN ru.LatestQuestionTitle IS NULL THEN '(No posts)' ELSE ru.LatestQuestionTitle END AS LatestQuestionTitle,
   ru.LatestQuestionDate,
   COALESCE(tu.TagsAggregated, '(none)') AS TopTags
FROM RankedUsers ru
LEFT JOIN (
   SELECT tu.UserId,
          STRING_AGG(tu.TagName || ':' || tu.TagCount::text, ', ' ORDER BY tu.TagCount DESC) AS TagsAggregated
   FROM TagUsage tu
   GROUP BY tu.UserId
) tu ON tu.UserId = ru.Id
WHERE ru.Reputation > 1000
  AND (ru.QuestionCount + ru.AnswerCount) > 10
UNION ALL
SELECT
   -1 AS Id,
   'Community' AS DisplayName,
   SUM(u.Reputation) AS Reputation,
   SUM(us.QuestionCount) AS QuestionCount,
   SUM(us.AnswerCount) AS AnswerCount,
   SUM(us.TotalScore) AS TotalScore,
   AVG(us.AvgScore) AS AvgScore,
   SUM(COALESCE(bs.BadgeCount,0)) AS TotalBadges,
   SUM(COALESCE(bs.GoldBadges,0)) AS GoldBadges,
   SUM(COALESCE(bs.SilverBadges,0)) AS SilverBadges,
   SUM(COALESCE(bs.BronzeBadges,0)) AS BronzeBadges,
   NULL AS RepScoreRank,
   NULL AS ActivityRank,
   NULL AS LatestQuestionTitle,
   NULL AS LatestQuestionDate,
   NULL AS TopTags
FROM Users u
JOIN UserStats us ON us.Id = u.Id
LEFT JOIN BadgeStats bs ON bs.UserId = u.Id
WHERE u.Id = -1;