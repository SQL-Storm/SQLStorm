WITH
UserBadgeAgg AS (
  SELECT
    UserId,
    Class,
    COUNT(*) AS BadgeCount,
    BOOL_OR(TagBased) AS HasTagBasedBadge
  FROM Badges
  GROUP BY UserId, Class
),
UserQuestionStats AS (
  SELECT
    OwnerUserId,
    AVG(CASE WHEN Posts.PostTypeId = 1 THEN Score END) AS AvgQuestionScore,
    MAX(CASE WHEN Posts.PostTypeId = 1 THEN Score END) AS MaxQuestionScore,
    COUNT(CASE WHEN Posts.PostTypeId = 1 AND Posts.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 1 END) AS RecentQuestionCount,
    COUNT(CASE WHEN Posts.PostTypeId = 2 THEN 1 END) AS TotalAnswers
  FROM Posts
  WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
  GROUP BY OwnerUserId
),
UserClosedDuplicateQuestions AS (
  SELECT
    p.OwnerUserId,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS ClosedCount,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId END) AS DuplicatesDetected
  FROM Posts p
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
  WHERE p.PostTypeId = 1 AND p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),
UserExoticFlags AS (
  SELECT
    u.Id,
    CASE
      WHEN u.UpVotes - u.DownVotes > bot_values.CriticalVote THEN 'PositiveSurvivor'
      ELSE NULL
    END AS EcosystemLabels
  FROM Users u
  LEFT JOIN (
    -- placeholder for bot values table; replace with actual table/source if available
    SELECT 0 AS CriticalVote
  ) bot_values ON 1=1
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, bot_values.CriticalVote, u.UpVotes, u.DownVotes
)
SELECT
  u.Id,
  uba.Class,
  uba.BadgeCount,
  uba.HasTagBasedBadge,
  uqs.AvgQuestionScore,
  uqs.MaxQuestionScore,
  uqs.RecentQuestionCount,
  uqs.TotalAnswers,
  ucq.ClosedCount,
  ucq.DuplicatesDetected,
  uef.EcosystemLabels
FROM Users u
LEFT JOIN UserBadgeAgg uba ON u.Id = uba.UserId
LEFT JOIN UserQuestionStats uqs ON u.Id = uqs.OwnerUserId
LEFT JOIN UserClosedDuplicateQuestions ucq ON u.Id = ucq.OwnerUserId
LEFT JOIN UserExoticFlags uef ON u.Id = uef.Id;