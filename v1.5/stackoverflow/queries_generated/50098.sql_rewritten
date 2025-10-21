-- {"query": "50098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1115} 
WITH PopularTags AS (
  SELECT
    TagName
  FROM Tags
  WHERE
    Count > 10000 AND IsModeratorOnly = '0'
), UserTagPerformance AS (
  SELECT
    A.OwnerUserId,
    PT.TagName,
    COUNT(A.Id) AS AnswersInTag,
    SUM(A.Score) AS TotalScoreInTag,
    SUM(CASE WHEN Q.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS AcceptedAnswersInTag,
    AVG(A.Score) AS AvgScoreInTag
  FROM Posts AS Q
  INNER JOIN PopularTags AS PT
    ON Q.Tags LIKE '%<' || PT.TagName || '>%'
  INNER JOIN Posts AS A
    ON Q.Id = A.ParentId
  WHERE
    Q.PostTypeId = 1 AND A.PostTypeId = 2 AND A.OwnerUserId IS NOT NULL
  GROUP BY
    A.OwnerUserId,
    PT.TagName
), RankedExperts AS (
  SELECT
    OwnerUserId,
    TagName,
    TotalScoreInTag,
    AnswersInTag,
    AcceptedAnswersInTag,
    RANK() OVER (PARTITION BY TagName ORDER BY TotalScoreInTag DESC, AnswersInTag DESC) AS ExpertRank
  FROM UserTagPerformance
  WHERE
    TotalScoreInTag > 100 AND AnswersInTag > 10
), UserCommunityStats AS (
  SELECT
    UserId,
    SUM(CASE WHEN VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalVotesCast,
    SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven,
    SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) AS TotalBountyAmountGiven
  FROM Votes
  WHERE
    UserId IS NOT NULL
  GROUP BY
    UserId
), UserModerationHistory AS (
  SELECT
    UserId,
    COUNT(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEdits,
    COUNT(CASE WHEN PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
    COUNT(CASE WHEN PostHistoryTypeId = 11 THEN 1 END) AS ReopenVotes
  FROM PostHistory
  WHERE
    UserId IS NOT NULL
  GROUP BY
    UserId
), UserBadgeCounts AS (
  SELECT
    UserId,
    COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges
  GROUP BY
    UserId
)
SELECT
  U.DisplayName,
  U.Reputation,
  U.CreationDate,
  RE.TagName AS ExpertInTag,
  RE.ExpertRank,
  RE.TotalScoreInTag,
  RE.AnswersInTag,
  RE.AcceptedAnswersInTag,
  COALESCE(UBC.GoldBadges, 0) AS GoldBadges,
  COALESCE(UBC.SilverBadges, 0) AS SilverBadges,
  COALESCE(UMH.TotalEdits, 0) AS TotalEdits,
  COALESCE(UMH.CloseVotes, 0) AS CloseVotes,
  COALESCE(UMH.ReopenVotes, 0) AS ReopenVotes,
  COALESCE(UCS.TotalVotesCast, 0) AS TotalVotesCast,
  COALESCE(UCS.TotalBountyAmountGiven, 0) AS TotalBountyGiven,
  LatestAnswer.Body AS LatestAnswerBody,
  LatestAnswer.Score AS LatestAnswerScore
FROM RankedExperts AS RE
JOIN Users AS U
  ON RE.OwnerUserId = U.Id
LEFT JOIN UserCommunityStats AS UCS
  ON U.Id = UCS.UserId
LEFT JOIN UserModerationHistory AS UMH
  ON U.Id = UMH.UserId
LEFT JOIN UserBadgeCounts AS UBC
  ON U.Id = UBC.UserId
LEFT JOIN LATERAL (
  SELECT
    P_ans.Body,
    P_ans.Score
  FROM Posts AS P_q
  JOIN Posts AS P_ans
    ON P_q.Id = P_ans.ParentId
  WHERE
    P_q.PostTypeId = 1
    AND P_ans.PostTypeId = 2
    AND P_ans.OwnerUserId = U.Id
    AND P_q.Tags LIKE '%<' || RE.TagName || '>%'
  ORDER BY
    P_ans.CreationDate DESC
  LIMIT 1
) AS LatestAnswer
  ON TRUE
WHERE
  RE.ExpertRank <= 10 AND U.Reputation > 50000
ORDER BY
  RE.TagName,
  RE.ExpertRank;