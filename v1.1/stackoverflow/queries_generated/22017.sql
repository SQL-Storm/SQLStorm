-- {"query": "22017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 839} 
WITH PostMetrics AS (
  SELECT P.Id, P.Title, P.Score, P.CreationDate, P.OwnerUserId, P.ClosedDate,
         COUNT(C.Id) AS CommentCount,
         COUNT(PL.Id) AS LinkCount,
         COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS UpvoteCount,
         COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS DownvoteCount,
         ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS PostRank,
         AVG(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 8) AS AvgBountyGiven
  FROM Posts P
  LEFT JOIN Comments C ON P.Id = C.PostId
  LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
  LEFT JOIN Votes V ON P.Id = V.PostId
  WHERE P.PostTypeId = 1 AND P.Score IS NOT NULL
  GROUP BY P.Id, P.Title, P.Score, P.CreationDate, P.OwnerUserId, P.ClosedDate
),
UserAggregates AS (
  SELECT PM.OwnerUserId,
         COALESCE(SUM(PM.Score), 0) AS TotalScore,
         COALESCE(AVG(PM.CommentCount), 0) AS AvgComments,
         COALESCE(SUM(PM.LinkCount), 0) AS TotalLinks,
         COUNT(CASE WHEN PM.PostRank <= 3 THEN 1 END) AS Top3Posts,
         COUNT(CASE WHEN PM.ClosedDate IS NOT NULL THEN 1 END) AS ClosedQuestions
  FROM PostMetrics PM
  GROUP BY PM.OwnerUserId
),
ActiveUsers AS (
  SELECT U.Id, U.DisplayName, U.Reputation, U.CreationDate,
         UA.TotalScore, UA.AvgComments, UA.TotalLinks, UA.Top3Posts, UA.ClosedQuestions,
         (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
         COALESCE(UPPER(SUBSTRING(U.DisplayName, 1, 1)), 'X') AS FirstLetter,
         CASE WHEN U.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus
  FROM Users U
  LEFT JOIN UserAggregates UA ON U.Id = UA.OwnerUserId
  WHERE U.Reputation > 50
),
RankedUsers AS (
  SELECT *,
         ROW_NUMBER() OVER (ORDER BY TotalScore DESC, GoldBadges DESC, Reputation DESC) AS GlobalRank,
         DENSE_RANK() OVER (PARTITION BY FirstLetter ORDER BY TotalScore DESC) AS LetterRank
  FROM ActiveUsers
  WHERE TotalScore > 10
),
TopUsers AS (
  SELECT * FROM RankedUsers WHERE GlobalRank <= 100
  UNION
  SELECT * FROM RankedUsers WHERE LetterRank <= 5 AND GoldBadges > 0
),
FinalUsers AS (
  SELECT DISTINCT Id, DisplayName, Reputation, CreationDate, TotalScore, AvgComments, TotalLinks, Top3Posts, ClosedQuestions, GoldBadges, FirstLetter, WebsiteStatus, GlobalRank, LetterRank
  FROM TopUsers
)
SELECT FU.*,
       (SELECT STRING_AGG(DISTINCT T.TagName, '; ')
        FROM Posts P
        CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag
        JOIN Tags T ON T.TagName = tag
        WHERE P.OwnerUserId = FU.Id AND P.PostTypeId = 1 AND T.Count > 100
        ORDER BY T.Count DESC
        LIMIT 5) AS PopularTags,
       GlobalRank + LetterRank AS CombinedRank
FROM FinalUsers FU
WHERE FU.Reputation IS NOT NULL AND FU.TotalScore > FU.ClosedQuestions * 5
ORDER BY CombinedRank, TotalScore DESC
LIMIT 200;