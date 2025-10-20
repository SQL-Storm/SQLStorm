WITH 
RecentActiveUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn,
         COUNT(*) OVER () AS total_users
  FROM Users u
  WHERE u.Reputation > 2000 
    AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
    AND u.Location IS NOT NULL
    AND u.DisplayName IS NOT NULL
),
UserBadgesSummary AS (
  SELECT b.UserId,
         COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
         COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
         COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
         BOOL_OR(b.TagBased) AS has_tag_based_badge,
         MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
UserQuestionStats AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') AS questions_180d,
         AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_question_score,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS total_questions,
         COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS questions_with_accepted_answer
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
UserAnswerQps AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
         MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS max_answer_score,
         AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_answer_score,
         STDDEV_POP(p.Score) FILTER (WHERE p.PostTypeId = 2) AS stddev_answer_score
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
TopDuplicateSources AS (
  SELECT pl.RelatedPostId AS QuestionId, COUNT(*) AS duplicate_count
  FROM PostLinks pl
  JOIN Posts p ON pl.PostId = p.Id 
  WHERE pl.LinkTypeId = 3 AND p.PostTypeId = 1
  GROUP BY pl.RelatedPostId
  HAVING COUNT(*) > 5
),
OldestCloseVotes AS (
  SELECT ph.PostId, ph.CreationDate, crt.Name AS CloseReasonName,
         ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS rn
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
  WHERE ph.PostHistoryTypeId = 10
),
FilteredCloseVotes AS (
  SELECT ocv.PostId, ocv.CreationDate, ocv.CloseReasonName
  FROM OldestCloseVotes ocv
  WHERE ocv.rn = 1
),
UserEngagement AS (
  SELECT c.UserId,
         COUNT(c.Id) FILTER (WHERE c.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days' AND CAST('2024-10-01 12:34:56' AS timestamp)) AS recent_comments,
         COUNT(v.Id) FILTER (WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') AS recent_votes,
         SUM(COALESCE(v.BountyAmount,0)) AS total_bounty_given
  FROM (
    SELECT UserId, Id, CreationDate FROM Comments WHERE UserId IS NOT NULL
  ) c
  LEFT JOIN Votes v ON v.UserId = c.UserId
  GROUP BY c.UserId
),
ComplexUserScores AS (
  SELECT 
    rau.Id, rau.DisplayName, rau.Reputation,
    COALESCE(ubs.gold_badges, 0) * 10 + COALESCE(ubs.silver_badges, 5) + COALESCE(ubs.bronze_badges, 1) AS badge_weight,
    COALESCE(uqs.questions_180d, 0) * 2 + COALESCE(uqs.avg_question_score, 0) AS question_scores,
    COALESCE(uap.answers_count, 0) * 1.5 + COALESCE(uap.avg_answer_score, 0) * 3 AS answer_scores,
    COALESCE(ue.recent_comments,0) + COALESCE(ue.recent_votes,0) / NULLIF(LEAST(ue.recent_votes+1,1000),0) AS engagement_ratio,
    rau.rn,
    rau.total_users,
    (CASE WHEN ubs.has_tag_based_badge THEN 'Yes' ELSE 'No' END) AS HasTagBasedBadge
  FROM RecentActiveUsers rau
  LEFT JOIN UserBadgesSummary ubs ON ubs.UserId = rau.Id
  LEFT JOIN UserQuestionStats uqs ON uqs.UserId = rau.Id
  LEFT JOIN UserAnswerQps uap ON uap.UserId = rau.Id
  LEFT JOIN UserEngagement ue ON ue.UserId = rau.Id
  WHERE rau.rn <= 10000
)
SELECT 
  cus.Id,
  cus.DisplayName,
  cus.Reputation,
  cus.badge_weight,
  cus.question_scores,
  cus.answer_scores,
  cus.engagement_ratio,
  cus.HasTagBasedBadge,
  fsq.Title AS LatestHighScoreQuestion,
  tq.DuplicateCount,
  CASE 
    WHEN fcw.CloseReasonName IS NOT NULL THEN CONCAT('Closed: ', fcw.CloseReasonName)
    ELSE 'Open'
  END AS CloseStatus,
  LEFT(cus.DisplayName, 3) || '-' || CAST(cus.rn AS varchar) AS UserCode
FROM ComplexUserScores cus
LEFT JOIN LATERAL (
  SELECT p.Id, p.Title, p.Score, p.CreationDate
  FROM Posts p
  WHERE p.OwnerUserId = cus.Id AND p.PostTypeId = 1
  ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC
  LIMIT 1
) fsq ON TRUE
LEFT JOIN (
  SELECT QuestionId, MAX(duplicate_count) AS DuplicateCount
  FROM TopDuplicateSources
  GROUP BY QuestionId
) tq ON tq.QuestionId = fsq.Id
LEFT JOIN FilteredCloseVotes fcw ON fcw.PostId = (
  SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = cus.Id AND p2.PostTypeId = 1 ORDER BY p2.LastActivityDate DESC LIMIT 1
)
WHERE 
  (cus.engagement_ratio * (1 + cus.answer_scores/100.0)) > 2.5 
  AND (cus.badge_weight + cus.question_scores + cus.answer_scores) > 25
ORDER BY cus.badge_weight DESC, cus.answer_scores DESC, cus.engagement_ratio DESC
LIMIT 50;