WITH
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
BadgesByUser AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopTagStats AS (
  SELECT
    tags.tag AS TagName,
    COUNT(*) AS TagUsage,
    AVG(u.Reputation) AS AvgReputation
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
  ) tags
  JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY tags.tag
  ORDER BY TagUsage DESC
  LIMIT 10
),
AllTagUsage AS (
  SELECT
    tags.tag AS TagName,
    COUNT(*) AS TagUsage,
    AVG(u.Reputation) AS AvgReputation
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
  ) tags
  JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY tags.tag
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.AccountId,
  ps.QuestionCount,
  ps.AnswerCount,
  ps.TotalQuestionScore,
  ps.TotalAnswerScore,
  ps.LastActivity,
  COALESCE(bb.BadgesCount, 0) AS BadgesCount,
  COALESCE(bb.GoldBadges, 0) AS GoldBadges,
  COALESCE(bb.SilverBadges, 0) AS SilverBadges,
  COALESCE(bb.BronzeBadges, 0) AS BronzeBadges,
  CASE
    WHEN u.Reputation > 2000 THEN 'Veteran'
    WHEN u.Reputation > 500 THEN 'Contributor'
    ELSE 'Newbie'
  END AS UserTier,
  array_remove(array_agg(DISTINCT tags.tag) FILTER (WHERE tags.tag IS NOT NULL), NULL) AS TopTags,
  at.TagUsage AS TopTagUsage,
  at.AvgReputation AS TopTagAvgReputation
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN UserStats ps ON ps.UserId = u.Id
  LEFT JOIN BadgesByUser bb ON bb.UserId = u.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
  ) tags ON p.Tags IS NOT NULL
  LEFT JOIN AllTagUsage at ON at.TagName = tags.tag
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.Location, u.Views, u.UpVotes, u.DownVotes,
  u.AccountId, ps.QuestionCount, ps.AnswerCount, ps.TotalQuestionScore, ps.TotalAnswerScore,
  ps.LastActivity, bb.BadgesCount, bb.GoldBadges, bb.SilverBadges, bb.BronzeBadges,
  at.TagUsage, at.AvgReputation
ORDER BY
  u.Reputation DESC,
  ps.LastActivity DESC
LIMIT 100;