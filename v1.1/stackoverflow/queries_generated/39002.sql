-- {"query": "39002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3244} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id,
      p.Title,
      p.CreationDate,
      u.DisplayName AS Author,
      p.Tags,
      p.OwnerUserId,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS TopViewedRank
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '30 days'
  ),

  TagExplode AS (
    SELECT
      rq.*,
      UNNEST(string_to_array(substring(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS Tag
    FROM RecentQuestions rq
  ),

  AnswerStats AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(*)            AS TotalAnswers,
      AVG(a.Score)        AS AvgAnswerScore,
      MAX(a.Score)        AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY a.ParentId
  ),

  VoteStats AS (
    SELECT
      v.PostId AS QuestionId,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites
    FROM Votes v
    WHERE v.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY v.PostId
  ),

  CommentStats AS (
    SELECT
      c.PostId AS QuestionId,
      COUNT(*)        AS CommentCount,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY c.PostId
  ),

  BadgeStats AS (
    SELECT
      b.UserId,
      COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
      COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
      COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
  ),

  UserRanking AS (
    SELECT
      bs.UserId,
      u.DisplayName AS BadgeOwner,
      bs.Gold,
      bs.Silver,
      bs.Bronze,
      RANK() OVER (
        ORDER BY (bs.Gold * 3 + bs.Silver * 2 + bs.Bronze) DESC
      ) AS BadgeRank
    FROM BadgeStats bs
    JOIN Users u ON u.Id = bs.UserId
  )

SELECT
  rq.Id            AS QuestionID,
  rq.Title,
  rq.Author,
  rq.TopViewedRank,
  ARRAY_AGG(DISTINCT te.Tag) AS Tags,
  ast.TotalAnswers,
  ast.AvgAnswerScore,
  ast.MaxAnswerScore,
  vst.UpVotes,
  vst.DownVotes,
  vst.Favorites,
  cst.CommentCount,
  cst.LastCommentDate,
  ur.Gold       AS UserGold,
  ur.Silver     AS UserSilver,
  ur.Bronze     AS UserBronze,
  ur.BadgeRank,
  LAG(vst.UpVotes) OVER (ORDER BY rq.TopViewedRank)  AS PrevUpVotes,
  LEAD(vst.UpVotes) OVER (ORDER BY rq.TopViewedRank) AS NextUpVotes
FROM RecentQuestions rq
LEFT JOIN TagExplode      te  ON te.Id          = rq.Id
LEFT JOIN AnswerStats     ast ON ast.QuestionId = rq.Id
LEFT JOIN VoteStats       vst ON vst.QuestionId = rq.Id
LEFT JOIN CommentStats    cst ON cst.QuestionId = rq.Id
LEFT JOIN UserRanking     ur  ON ur.UserId      = rq.OwnerUserId
GROUP BY
  rq.Id,
  rq.Title,
  rq.Author,
  rq.TopViewedRank,
  ast.TotalAnswers,
  ast.AvgAnswerScore,
  ast.MaxAnswerScore,
  vst.UpVotes,
  vst.DownVotes,
  vst.Favorites,
  cst.CommentCount,
  cst.LastCommentDate,
  ur.Gold,
  ur.Silver,
  ur.Bronze,
  ur.BadgeRank
ORDER BY rq.TopViewedRank
LIMIT 50;
