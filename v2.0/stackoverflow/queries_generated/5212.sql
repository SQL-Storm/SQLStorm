-- {"query": "5212.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 997} 
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
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  GROUP BY
    u.Id
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
    t.TagName,
    COUNT(*) AS TagUsage,
    AVG(u.Reputation) AS AvgReputation
  FROM Posts p
  JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag
      ON TRUE
  JOIN Users u ON u.Id = p.OwnerUserId
  JOIN Tags tt ON tt.TagName = tag
  GROUP BY t.TagName
  ORDER BY TagUsage DESC
  LIMIT 10
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
  COALESCE bb.BadgesCount, 0 AS BadgesCount,
  COALESCE bb.GoldBadges, 0 AS GoldBadges,
  COALESCE bb.SilverBadges, 0 AS SilverBadges,
  COALESCE bb.BronzeBadges, 0 AS BronzeBadges,
  CASE
    WHEN u.Reputation > 2000 THEN 'Veteran'
    WHEN u.Reputation > 500 THEN 'Contributor'
    ELSE 'Newbie'
  END AS UserTier,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TopTags,
  tgs.TagUsage AS TopTagUsage,
  tgs.AvgReputation AS TopTagAvgReputation
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN UserStats ps ON ps.UserId = u.Id
  LEFT JOIN BadgesByUser bb ON bb.UserId = u.Id
  LEFT JOIN (
    SELECT
      tt.TagName,
      COUNT(*) AS TagUsage
    FROM Posts pp
    JOIN LATERAL string_to_array(substring(pp.Tags, 2, length(pp.Tags)-2), '><') AS tag
        ON TRUE
    JOIN Tags t ON t.TagName = tag
    GROUP BY tt.TagName
  ) tgs ON true
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON true
  LEFT JOIN Tags t ON t.TagName = t.TagName
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.Location, u.Views, u.UpVotes, u.DownVotes,
  u.AccountId, ps.QuestionCount, ps.AnswerCount, ps.TotalQuestionScore, ps.TotalAnswerScore,
  ps.LastActivity, bb.BadgesCount, bb.GoldBadges, bb.SilverBadges, bb.BronzeBadges,
  tgs.TagUsage, tgs.AvgReputation
ORDER BY
  u.Reputation DESC,
  ps.LastActivity DESC
LIMIT 100;