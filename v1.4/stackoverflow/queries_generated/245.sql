-- {"query": "245.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10853} 
WITH
PA AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) AS TotalPosts,
         COALESCE(SUM(ViewCount),0) AS TotalViews,
         MAX(CreationDate) AS LastPostDate,
         MAX(LastEditDate) AS LastEditDate,
         SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
         AVG(Score) AS AvgPostScore
  FROM Posts
  GROUP BY OwnerUserId
),
VA AS (
  SELECT P.OwnerUserId AS UserId,
         SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
         SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
  FROM Posts P
  LEFT JOIN Votes V ON V.PostId = P.Id
  GROUP BY P.OwnerUserId
),
CA AS (
  SELECT P.OwnerUserId AS UserId,
         SUM(CASE WHEN C.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount
  FROM Posts P
  LEFT JOIN Comments C ON C.PostId = P.Id
  GROUP BY P.OwnerUserId
),
BA AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
TT AS (
  SELECT UserId, TopTag
  FROM (
    SELECT UserId, Tag AS TopTag, Cnt,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Cnt DESC) AS rn
    FROM (
      SELECT P.OwnerUserId AS UserId,
             t.tag AS Tag,
             COUNT(*) AS Cnt
      FROM Posts P
      CROSS JOIN LATERAL unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS t(tag)
      WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId = 1
      GROUP BY P.OwnerUserId, t.tag
    ) s
  ) t2
  WHERE rn = 1
),
CV AS (
  SELECT U.Id AS UserId,
         (
           SELECT COUNT(*) 
           FROM PostHistory PH
           WHERE PH.PostId IN (SELECT Id FROM Posts P2 WHERE P2.OwnerUserId = U.Id)
             AND PH.PostHistoryTypeId = 10
         ) AS CloseHistoryCount
  FROM Users U
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(pa.TotalPosts, 0) AS TotalPosts,
  COALESCE(pa.TotalViews, 0) AS TotalViews,
  pa.LastPostDate AS LastPostDate,
  COALESCE(pa.QuestionCount, 0) AS QuestionCount,
  COALESCE(pa.AnswerCount, 0) AS AnswerCount,
  COALESCE(pa.AvgPostScore, 0) AS AvgPostScore,
  COALESCE(va.UpVotesReceived, 0) AS UpVotesReceived,
  COALESCE(va.DownVotesReceived, 0) AS DownVotesReceived,
  COALESCE(ca.CommentCount, 0) AS CommentCount,
  COALESCE(ba.GoldBadges, 0) AS GoldBadges,
  COALESCE(ba.SilverBadges, 0) AS SilverBadges,
  COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
  TT.TopTag AS TopTag,
  COALESCE(cv.CloseHistoryCount, 0) AS CloseHistoryCount
FROM Users u
LEFT JOIN PA pa ON pa.UserId = u.Id
LEFT JOIN VA va ON va.UserId = u.Id
LEFT JOIN CA ca ON ca.UserId = u.Id
LEFT JOIN BA ba ON ba.UserId = u.Id
LEFT JOIN TT ON TT.UserId = u.Id
LEFT JOIN CV cv ON cv.UserId = u.Id
ORDER BY u.Reputation DESC NULLS LAST
LIMIT 200;