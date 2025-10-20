-- {"query": "202.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9239} 
WITH
UserExtras AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         CONCAT_WS(' | ', COALESCE(u.DisplayName, ''), COALESCE(u.Location, ''), TO_CHAR(u.CreationDate, 'YYYY-MM-DD')) AS ProfileTag
  FROM Users u
),
TopQuestions AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    'Question' AS PostKind,
    ue.DisplayName AS DisplayName,
    p.Title,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST) AS PerUserRank,
    (p.ViewCount * 3 + p.Score) AS RankScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesOnPost,
    ue.Reputation,
    ue.ProfileTag
  FROM Posts p
  JOIN UserExtras ue ON ue.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
  ORDER BY RankScore DESC NULLS LAST
  LIMIT 200
),
TopAnswers AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    'Answer' AS PostKind,
    ue.DisplayName AS DisplayName,
    p.Title,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST) AS PerUserRank,
    (p.Score * 4 + p.ViewCount) AS RankScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesOnPost,
    ue.Reputation,
    ue.ProfileTag
  FROM Posts p
  JOIN UserExtras ue ON ue.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 2
  ORDER BY RankScore DESC NULLS LAST
  LIMIT 200
),
Combined AS (
  SELECT * FROM TopQuestions
  UNION ALL
  SELECT * FROM TopAnswers
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  PostId,
  PostKind,
  Title,
  ViewCount,
  Score,
  LastActivityDate,
  RankScore,
  PerUserRank,
  CommentCount,
  UpVotesOnPost,
  ProfileTag
FROM Combined
ORDER BY Reputation DESC NULLS LAST, RankScore DESC NULLS LAST
LIMIT 500;