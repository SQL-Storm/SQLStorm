WITH RecursiveUserSiteActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpVotesReceived,
        COUNT(DISTINCT CASE WHEN c.UserId = u.Id THEN c.Id END) AS CommentsMade,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Location IS NOT NULL
      AND u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '5' YEAR
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
QuestionsWithLinkedDuplicates AS (
    SELECT 
        p.Id AS QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(pl_dup.CountDup,-1) AS DuplicateCount,
        COALESCE(pl_link.CountLinked,-1) AS LinkedCount,
        COALESCE(ph.CloseTimes,0) AS CloseCount,
        p.OwnerUserId
    FROM Posts p 
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountDup
        FROM PostLinks
        WHERE LinkTypeId = 3
        GROUP BY PostId
    ) pl_dup ON pl_dup.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountLinked
        FROM PostLinks 
        WHERE LinkTypeId = 1
        GROUP BY PostId
    ) pl_link ON pl_link.PostId = p.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS CloseTimes
      FROM PostHistory 
      WHERE PostHistoryTypeId = 10 
      GROUP BY PostId
    ) ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
),
ExpensiveAggregations AS (
    SELECT 
        q.QuestionId,
        q.Score,
        q.ViewCount,
        q.DuplicateCount,
        q.LinkedCount,
        q.CloseCount,
        (
            SELECT AVG(p_sub.Score)
            FROM Posts p_sub
            WHERE p_sub.ParentId = q.QuestionId
        ) AS ImpliedAvgAnswerScore,
        COUNT(b.Id) AS GoldBadgesCollected,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END) AS DistinctGoldBadgeCount
    FROM QuestionsWithLinkedDuplicates q
    LEFT JOIN Badges b on b.UserId = q.OwnerUserId
    GROUP BY q.QuestionId, q.Score, q.ViewCount, q.DuplicateCount, q.LinkedCount, q.CloseCount
),
UserFirstQuestion AS (
    -- determine one question per user to join without using a non-inner join on a subquery in the JOIN clause
    SELECT p.OwnerUserId AS UserId, MIN(p.Id) AS QuestionId
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
FinalRanking AS (
    SELECT
      u.UserId,
      u.DisplayName,
      u.Reputation,
      u.QuestionsPosted,
      u.TotalUpVotesReceived,
      u.CommentsMade,
      u.Location,
      CASE WHEN COALESCE(u.Location, '') = '' THEN FALSE ELSE TRUE END AS HasValidLocationName,
      eu.QuestionId,
      eu.Score,
      eu.ViewCount,
      eu.DuplicateCount,
      eu.LinkedCount,
      eu.CloseCount,
      eu.ImpliedAvgAnswerScore,
      eu.GoldBadgesCollected,
      eu.DistinctGoldBadgeCount,
      RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) As RankWithinLoc
    FROM RecursiveUserSiteActivity u
    LEFT JOIN UserFirstQuestion uq ON uq.UserId = u.UserId
    LEFT JOIN ExpensiveAggregations eu ON eu.QuestionId = uq.QuestionId
    WHERE u.Reputation > 1500
)
SELECT 
  fr.DisplayName, 
  fr.Location, 
  fr.Reputation, 
  fr.QuestionsPosted,
  fr.CommentsMade,
  fr.TotalUpVotesReceived,
  fr.QuestionId,
  fr.Score AS QuestionScore,
  fr.ViewCount,
  COALESCE(fr.DuplicateCount, 0) AS QuestionDuplicates,
  COALESCE(fr.LinkedCount, 0) AS QuestionLinkedCount,
  COALESCE(fr.CloseCount,0) AS CloseVotes,
  ROUND(COALESCE(fr.ImpliedAvgAnswerScore, 0), 2) AS AvgAnswerScore,
  fr.GoldBadgesCollected,
  fr.DistinctGoldBadgeCount,
  fr.RankWithinLoc
FROM FinalRanking fr
WHERE fr.QuestionId IS NOT NULL AND fr.RankWithinLoc <= 10

UNION ALL

SELECT
  u.DisplayName,
  u.Location,
  u.Reputation,
  0 AS QuestionsPosted,
  0 AS CommentsMade,
  0 AS TotalUpVotesReceived,
  NULL AS QuestionId,
  NULL AS QuestionScore,
  NULL AS ViewCount,
  0 AS QuestionDuplicates,
  0 AS QuestionLinkedCount,
  0 AS CloseVotes,
  NULL AS AvgAnswerScore,
  0 AS GoldBadgesCollected,
  0 AS DistinctGoldBadgeCount,
  NULL AS RankWithinLoc
FROM Users u
WHERE u.Reputation > 10000
  AND NOT EXISTS (
    SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id
)
ORDER BY Reputation DESC, Location NULLS LAST;