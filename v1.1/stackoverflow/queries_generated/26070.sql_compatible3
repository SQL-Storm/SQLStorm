WITH RankedPosts AS (
  SELECT 
    P.Id, 
    P.Score, 
    P.ViewCount, 
    P.CreationDate, 
    P.LastActivityDate, 
    ROW_NUMBER() OVER (ORDER BY P.Score DESC) AS RowNum,
    DENSE_RANK() OVER (ORDER BY P.Score DESC) AS DenseRank,
    P.OwnerUserId,
    P.Title,
    P.Tags
  FROM Posts P
),
Top100Posts AS (
  SELECT * 
  FROM RankedPosts 
  WHERE RowNum <= 100
),
UserPostStats AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    COUNT(DISTINCT P.Id) AS PostCount, 
    SUM(P.Score) AS TotalScore
  FROM Users U
  LEFT JOIN Posts P ON U.Id = P.OwnerUserId
  GROUP BY U.Id, U.DisplayName
),
TopVoters AS (
  SELECT 
    V.UserId, 
    COUNT(DISTINCT V.Id) AS VoteCount
  FROM Votes V
  GROUP BY V.UserId
  ORDER BY VoteCount DESC
  LIMIT 10
)
SELECT 
  P.Id, 
  P.Title, 
  P.Score, 
  P.ViewCount, 
  P.CreationDate, 
  P.LastActivityDate, 
  U.DisplayName AS OwnerDisplayName, 
  U.Reputation AS OwnerReputation, 
  UPS.PostCount AS OwnerPostCount, 
  UPS.TotalScore AS OwnerTotalScore, 
  TV.VoteCount AS OwnerVoteCount,
  (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P.Id) AS CommentCount,
  (SELECT COUNT(*) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS CloseVoteCount,
  (SELECT COUNT(*) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS LinkedPostCount,
  (
    SELECT COUNT(*) 
    FROM Tags T 
    WHERE T.TagName IN (
      SELECT TRIM(value) 
      FROM (
        SELECT value
        FROM UNNEST(
          regexp_split_to_array(
            CASE 
              WHEN P.Tags IS NULL THEN ''
              ELSE substring(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2)
            END,
          '><')
        ) AS t(value)
      ) AS sub
    )
    AND T.IsModeratorOnly = FALSE
  ) AS TagCount
FROM Top100Posts P
LEFT JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN UserPostStats UPS ON U.Id = UPS.Id
LEFT JOIN TopVoters TV ON U.Id = TV.UserId
GROUP BY
  P.Id,
  P.Title,
  P.Score,
  P.ViewCount,
  P.CreationDate,
  P.LastActivityDate,
  P.OwnerUserId,
  P.Tags,
  U.DisplayName,
  U.Reputation,
  UPS.PostCount,
  UPS.TotalScore,
  TV.VoteCount
ORDER BY P.Score DESC;