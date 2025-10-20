-- {"query": "54040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 3274} 
WITH
  -- Base questions with essential columns
  question_posts AS (
    SELECT
      p.Id          AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.Title,
      p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),

  -- Vote statistics per question
  vote_stats AS (
    SELECT
      v.PostId,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
      COUNT(*) FILTER (WHERE v.VoteTypeId = 1) AS AcceptedVotes
    FROM Votes v
    GROUP BY v.PostId
  ),

  -- Edit statistics per question
  edit_stats AS (
    SELECT
      ph.PostId,
      COUNT(*)                AS EditCount,
      MIN(ph.CreationDate)    AS FirstEdit,
      MAX(ph.CreationDate)    AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)   -- edit actions
    GROUP BY ph.PostId
  ),

  -- Expand tags into one row per tag
  tags_expanded AS (
    SELECT
      q.QuestionId,
      TRIM(BOTH '><' FROM unnest(string_to_array(q.Tags, '> <'))) AS Tag
    FROM question_posts q
    WHERE q.Tags IS NOT NULL
  ),

  -- Tag usage counts (for popularity metric)
  tag_counts AS (
    SELECT
      Tag,
      COUNT(*) AS TagUsage
    FROM tags_expanded
    GROUP BY Tag
  ),

  -- User badge counts
  badge_counts AS (
    SELECT
      b.UserId,
      SUM(CASE WHEN b.Class = 1 THEN 1 END) AS Gold,
      SUM(CASE WHEN b.Class = 2 THEN 1 END) AS Silver,
      SUM(CASE WHEN b.Class = 3 THEN 1 END) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
  ),

  -- Consolidated user statistics
  user_stats AS (
    SELECT
      u.Id          AS UserId,
      u.Reputation,
      COALESCE(bc.Gold,   0) AS GoldBadges,
      COALESCE(bc.Silver,0) AS SilverBadges,
      COALESCE(bc.Bronze,0) AS BronzeBadges
    FROM Users u
    LEFT JOIN badge_counts bc ON bc.UserId = u.Id
  )

SELECT
  qp.QuestionId,
  qp.Title,
  qp.OwnerUserId,
  qp.Score,
  qp.ViewCount,
  qp.AnswerCount,
  COALESCE(vs.UpVotes, 0)      AS UpVotes,
  COALESCE(vs.DownVotes, 0)    AS DownVotes,
  COALESCE(vs.AcceptedVotes, 0) AS AcceptedVotes,
  COALESCE(es.EditCount, 0)     AS EditCount,
  es.FirstEdit,
  es.LastEdit,
  us.Reputation,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges,
  ARRAY_AGG(DISTINCT te.Tag)    AS Tags,
  (SELECT COALESCE(SUM(tc.TagUsage),0) FROM tag_counts tc
   WHERE tc.Tag = ANY(ARRAY_AGG(DISTINCT te.Tag))) AS Popularity
FROM question_posts qp
LEFT JOIN vote_stats vs  ON vs.PostId = qp.QuestionId
LEFT JOIN edit_stats es  ON es.PostId = qp.QuestionId
LEFT JOIN tags_expanded te ON te.QuestionId = qp.QuestionId
LEFT JOIN user_stats us  ON us.UserId = qp.OwnerUserId
GROUP BY
  qp.QuestionId,
  qp.Title,
  qp.OwnerUserId,
  qp.Score,
  qp.ViewCount,
  qp.AnswerCount,
  vs.UpVotes,
  vs.DownVotes,
  vs.AcceptedVotes,
  es.EditCount,
  es.FirstEdit,
  es.LastEdit,
  us.Reputation,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges
ORDER BY qp.Score DESC NULLS LAST, qp.AnswerCount DESC NULLS LAST
LIMIT 100;