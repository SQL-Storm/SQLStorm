-- {"query": "1070.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1477} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.ExcerptPostId, 1 AS Depth
    FROM Tags t
    WHERE t.IsRequired = 1
  UNION ALL
    SELECT t.Id, t.TagName, t.ExcerptPostId, r.Depth + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.ExcerptPostId = r.ExcerptPostId
    WHERE r.Depth < 5
),
RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate > CURRENT_DATE - INTERVAL '180 days') AS RecentQuestions,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate > CURRENT_DATE - INTERVAL '180 days') AS RecentAnswers,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS RecentUpVotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS RecentDownVotes,
           RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate > CURRENT_DATE - INTERVAL '180 days'
    WHERE u.LastAccessDate > CURRENT_DATE - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) FILTER (WHERE p.CreationDate > CURRENT_DATE - INTERVAL '180 days') > 0
),
QuestionWithAnswersAndComments AS (
    SELECT q.Id AS QuestionId, q.Title, q.Tags, q.CreationDate, q.Score AS QuestionScore, q.ViewCount,
           COUNT(DISTINCT a.Id) AS AnswerCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           SUM(COALESCE(a.Score,0)) AS TotalAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount
),
UserBadgesSummary AS (
    SELECT b.UserId,
           COUNT(*) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.TagBased = 1) AS TagBasedBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostCloseReasons AS (
    SELECT ph.PostId, cr.Name AS CloseReasonName,
           COUNT(*) AS CloseVotes
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS INT) AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, cr.Name
),
TopUsersWithActivity AS (
    SELECT u.Id, u.DisplayName, u.Reputation, ua.RecentQuestions, ua.RecentAnswers,
           ua.RecentUpVotes, ua.RecentDownVotes, ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM Users u
    LEFT JOIN RecentActiveUsers ua ON ua.Id = u.Id
    LEFT JOIN UserBadgesSummary ubs ON ubs.UserId = u.Id
    WHERE u.Reputation > 1000
),
QuestionAnswerVoteStats AS (
    SELECT q.Id AS QuestionId,
           COUNT(DISTINCT a.Id) AS AnswerCount,
           SUM(COALESCE(vup.VoteTypeId = 2::int,0)) AS TotalUpVotes,
           SUM(COALESCE(vdn.VoteTypeId = 3::int,0)) AS TotalDownVotes,
           MAX(COALESCE(p.Score,0)) AS MaxScoreAnswer
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes vup ON vup.PostId = a.Id AND vup.VoteTypeId = 2
    LEFT JOIN Votes vdn ON vdn.PostId = a.Id AND vdn.VoteTypeId = 3
    LEFT JOIN Posts p ON p.Id = a.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
)
SELECT
  topU.UserRank,
  topU.DisplayName,
  topU.Reputation,
  topU.RecentQuestions,
  topU.RecentAnswers,
  topU.RecentUpVotes,
  topU.RecentDownVotes,
  topU.TotalBadges,
  topU.GoldBadges,
  topU.SilverBadges,
  topU.BronzeBadges,
  qac.QuestionId,
  qac.Title AS QuestionTitle,
  qac.Tags,
  qac.CreationDate AS QuestionDate,
  qac.QuestionScore,
  qac.ViewCount,
  qac.AnswerCount,
  qac.CommentCount,
  qac.TotalAnswerScore,
  pcr.CloseReasonName,
  pcr.CloseVotes,
  CASE WHEN qac.CommentCount > 5 THEN 'Highly Commented' ELSE 'Less Commented' END AS CommentLevel,
  rh.Depth AS TagHierarchyDepth,
  COALESCE(ubs.TagBasedBadgeNames, 'None') AS TagBadges,
  (SELECT COUNT(1) FROM Comments c WHERE c.PostId = qac.QuestionId AND c.UserId = topU.Id) AS UserCommentsOnQuestion,
  ROW_NUMBER() OVER (PARTITION BY topU.UserRank ORDER BY qac.ViewCount DESC) AS UserTopQuestionRank
FROM TopUsersWithActivity topU
LEFT JOIN QuestionWithAnswersAndComments qac ON qac.QuestionId IN (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = topU.Id AND p.PostTypeId = 1
)
LEFT JOIN PostCloseReasons pcr ON pcr.PostId = qac.QuestionId
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(regexp_replace(qac.Tags, '[<>]', '', 'g'), ' '))
LEFT JOIN UserBadgesSummary ubs ON ubs.UserId = topU.Id
WHERE topU.UserRank <= 50
ORDER BY topU.UserRank, qac.ViewCount DESC
LIMIT 200;
