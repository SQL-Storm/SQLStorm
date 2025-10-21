-- {"query": "375.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 11832} 
WITH
GoldBadges AS (
  SELECT UserId, COUNT(*) AS GoldBadges
  FROM Badges
  WHERE Class = 1
  GROUP BY UserId
),
ParsedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COALESCE(g.GoldBadges, 0) AS GoldBadges,
    CASE WHEN p.Tags IS NULL THEN 0 ELSE array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) END AS TagCount,
    CASE WHEN 'c#' = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) THEN 1 ELSE 0 END AS HasCSharp
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN GoldBadges g ON p.OwnerUserId = g.UserId
  WHERE p.PostTypeId = 1
),
ScoreRank AS (
  SELECT
    Id,
    Title,
    Tags,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    CreationDate,
    OwnerUserId,
    OwnerName,
    Reputation,
    GoldBadges,
    TagCount,
    HasCSharp,
    ROW_NUMBER() OVER (
      ORDER BY (
        Score * 0.6 +
        ViewCount * 0.2 +
        COALESCE(AnswerCount, 0) * 2 +
        COALESCE(CommentCount, 0) * 0.5 +
        COALESCE((SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = Id OR pl.RelatedPostId = Id), 0) * 0.8
      ) DESC
    ) AS rn_score,
    (SELECT MAX(CreationDate) FROM Comments c2 WHERE c2.PostId = Id) AS LastCommentDate
  FROM ParsedPosts
),
ViewRank AS (
  SELECT
    Id,
    Title,
    Tags,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    CreationDate,
    OwnerUserId,
    OwnerName,
    Reputation,
    GoldBadges,
    TagCount,
    HasCSharp,
    ROW_NUMBER() OVER (ORDER BY ViewCount DESC) AS rn_view,
    (SELECT MAX(CreationDate) FROM Comments c2 WHERE c2.PostId = Id) AS LastCommentDate
  FROM ParsedPosts
)
SELECT *
FROM (
  SELECT
    Id, Title, Tags, Score, ViewCount, AnswerCount, CommentCount, CreationDate,
    OwnerUserId, OwnerName, Reputation, GoldBadges, TagCount, HasCSharp,
    LastCommentDate,
    rn_score AS rank,
    'SCORE' AS Source
  FROM ScoreRank
  WHERE rn_score <= 200
  UNION ALL
  SELECT
    Id, Title, Tags, Score, ViewCount, AnswerCount, CommentCount, CreationDate,
    OwnerUserId, OwnerName, Reputation, GoldBadges, TagCount, HasCSharp,
    LastCommentDate,
    rn_view AS rank,
    'VIEW' AS Source
  FROM ViewRank
  WHERE rn_view <= 200
) AS t
WHERE (LastCommentDate IS NULL OR LastCommentDate > CreationDate - INTERVAL '180 days')
ORDER BY rank, CreationDate DESC
LIMIT 500;