WITH TopUsers AS (
    SELECT U.Id AS UserId,
           U.DisplayName,
           U.Reputation,
           COUNT(DISTINCT P.Id) AS NumPosts,
           SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumQuestions,
           SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswers,
           DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS RepRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.CreationDate <= (SELECT MAX(CreationDate) FROM Users) - INTERVAL '1 year'
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING COUNT(P.Id) > 10
),
UserBadges AS (
    SELECT B.UserId,
           SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges,
           SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBadges,
           MIN(B.Date) AS FirstBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
ActivePosts AS (
    SELECT P.Id,
           P.OwnerUserId,
           P.Title,
           P.PostTypeId,
           P.CreationDate,
           P.LastActivityDate,
           P.Score,
           P.Tags,
           P.ClosedDate,
           P.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate DESC) AS RecentRank
    FROM Posts P
    WHERE P.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days')
      AND P.Score >= 1
      AND P.PostTypeId IN (1,2)
),
PivotedVotes AS (
    SELECT V.PostId,
           SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes V
    GROUP BY V.PostId
),
CommentStats AS (
    SELECT C.PostId,
           COUNT(*) AS NumComments,
           CAST(AVG(C.Score) AS DECIMAL(5,2)) AS AvgCommentScore,
           MAX(C.CreationDate) AS LastCommentDate,
           SUM(CASE WHEN C.Score >= 5 THEN 1 ELSE 0 END) AS HighScoreComments
    FROM Comments C
    GROUP BY C.PostId
)
SELECT
    T.UserId,
    T.DisplayName,
    T.Reputation,
    T.NumPosts,
    T.NumQuestions,
    T.NumAnswers,
    T.RepRank,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    UB.TotalBadges,
    UB.TagBadges,
    COALESCE(CAST(UB.FirstBadgeDate AS DATE), DATE '1970-01-01') AS FirstBadgeDate_temp,
    AP.Id AS RecentPostId,
    AP.Title AS RecentPostTitle,
    AP.PostTypeId,
    AP.CreationDate AS RecentPostCreated,
    AP.LastActivityDate,
    AP.Score AS RecentPostScore,
    CASE WHEN AP.Tags IS NULL THEN NULL
         ELSE regexp_split_to_array(substring(AP.Tags FROM 2 FOR (length(AP.Tags) - 2)), '><')
    END AS RecentPostTags,
    PV.UpVotes,
    PV.DownVotes,
    PV.Favorites,
    CS.NumComments,
    CS.AvgCommentScore,
    CASE 
        WHEN CS.HighScoreComments IS NULL OR CS.HighScoreComments = 0 THEN 'No High Score Comments'
        ELSE CAST(CS.HighScoreComments AS TEXT) || ' high score comment(s)'
    END AS HighScoreComments,
    CASE 
        WHEN AP.ClosedDate IS NOT NULL THEN 'Closed on ' || CAST(AP.ClosedDate AS DATE)
        ELSE 'Open'
    END AS PostState,
    (SELECT COUNT(*) FROM Posts P2 WHERE P2.OwnerUserId = T.UserId AND P2.Score > 5) AS HighlyUpvotedPosts,
    (SELECT AVG(P3.ViewCount) FROM Posts P3 WHERE P3.OwnerUserId = T.UserId AND P3.ViewCount IS NOT NULL) AS AvgViewCount
FROM TopUsers T
LEFT JOIN UserBadges UB ON T.UserId = UB.UserId
LEFT JOIN ActivePosts AP ON T.UserId = AP.OwnerUserId AND AP.RecentRank = 1
LEFT JOIN PivotedVotes PV ON AP.Id = PV.PostId
LEFT JOIN CommentStats CS ON AP.Id = CS.PostId
WHERE T.RepRank <= 50
ORDER BY T.RepRank, AP.LastActivityDate DESC;