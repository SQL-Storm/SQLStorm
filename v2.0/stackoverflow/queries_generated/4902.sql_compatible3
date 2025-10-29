WITH
  HighReputationUsers AS (
    SELECT
      U.Id,
      U.DisplayName,
      U.Reputation,
      (
        SELECT COUNT(*)
        FROM Posts P_Inner
        WHERE P_Inner.OwnerUserId = U.Id
          AND P_Inner.PostTypeId = 1
      ) AS QuestionCount
    FROM Users U
    WHERE U.Reputation > 10000
  ),
  UserActivity AS (
    SELECT
      U.Id AS UserId,
      U.DisplayName,
      COUNT(C.Id) AS CommentCount,
      SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users U
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Id IN (SELECT Id FROM HighReputationUsers)
    GROUP BY U.Id, U.DisplayName
  ),
  PostEngagement AS (
    SELECT
      P.Id AS PostId,
      P.Title,
      P.OwnerUserId,
      P.CreationDate,
      P.Score,
      P.AnswerCount,
      P.CommentCount,
      P.FavoriteCount,
      CASE
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate DESC) AS PostRank
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.OwnerUserId IS NOT NULL
      AND P.OwnerUserId <> -1
      AND P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
  )
SELECT
  HRU.DisplayName AS UserName,
  HRU.Reputation,
  HRU.QuestionCount,
  COALESCE(UA.CommentCount, 0) AS TotalComments,
  COALESCE(UA.UpVoteCount, 0) AS UpVoteCount,
  COALESCE(UA.DownVoteCount, 0) AS DownVoteCount,
  SUM(CASE WHEN PE.PostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedQuestions,
  AVG(PE.Score) AS AverageQuestionScore,
  MAX(PE.FavoriteCount) AS MaxFavoriteCount,
  (
    SELECT PHT.Name
    FROM PostHistoryTypes PHT
    WHERE PHT.Id = (
      SELECT PH_Inner.PostHistoryTypeId
      FROM PostHistory PH_Inner
      WHERE PH_Inner.PostId = PE.PostId
        AND PH_Inner.CreationDate = (
          SELECT MAX(PH_Max.CreationDate)
          FROM PostHistory PH_Max
          WHERE PH_Max.PostId = PE.PostId
            AND PH_Max.PostHistoryTypeId IN (4, 6)
        )
      ORDER BY PH_Inner.CreationDate DESC
      LIMIT 1
    )
    LIMIT 1
  ) AS LastEditType
FROM HighReputationUsers HRU
LEFT JOIN UserActivity UA ON HRU.Id = UA.UserId
LEFT JOIN PostEngagement PE ON HRU.Id = PE.OwnerUserId
WHERE PE.PostRank <= 5
GROUP BY
  HRU.Id,
  HRU.DisplayName,
  HRU.Reputation,
  HRU.QuestionCount,
  COALESCE(UA.CommentCount, 0),
  COALESCE(UA.UpVoteCount, 0),
  COALESCE(UA.DownVoteCount, 0),
  HRU.DisplayName, -- ensure any referenced columns in SELECT are grouped
  PE.PostStatus,
  PE.Score,
  PE.FavoriteCount,
  PE.PostId
HAVING
  COUNT(PE.PostId) > 0 OR COALESCE(UA.CommentCount, 0) > 0
ORDER BY
  HRU.Reputation DESC,
  TotalComments DESC;