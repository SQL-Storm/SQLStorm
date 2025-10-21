-- {"query": "24084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4160} 

WITH
  /* Questions that contain the <sql> tag */
  tag_posts AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.AnswerCount,
           p.CreationDate,
           p.LastActivityDate,
           p.Tags,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<sql>%'
  ),

  /* Earliest edit of each question (title/body/tags) */
  first_edit AS (
    SELECT PostId,
           MIN(CreationDate) AS FirstEditDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6)
    GROUP BY PostId
  ),

  /* Vote aggregates per post */
  vote_sums AS (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 END)   AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 END)   AS DownVotes,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1
                    WHEN VoteTypeId = 3 THEN -1 END) AS NetScore
    FROM Votes
    GROUP BY PostId
  ),

  /* Badge counts per user */
  badge_counts AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 END) AS Gold,
           SUM(CASE WHEN Class = 2 THEN 1 END) AS Silver,
           SUM(CASE WHEN Class = 3 THEN 1 END) AS Bronze
    FROM Badges
    GROUP BY UserId
  ),

  /* per‑user stats for <sql> questions */
  question_user_stats AS (
    SELECT u.Id             AS UserId,
           u.Reputation,
           COUNT(p.Id)       AS OwnedSqlQuestions,
           SUM(p.Score)      AS TotalQuestionScore,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RnkByReputation,
           STRING_AGG(p.Tags, ';') AS AllTags
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<sql>%'
    GROUP BY u.Id, u.Reputation
  ),

  /* Combine votes on questions and on answers to those questions */
  combined_votes AS (
    SELECT PostId, VoteTypeId
    FROM Votes
    WHERE PostId IN (SELECT Id FROM tag_posts)
    UNION ALL
    SELECT v.PostId, v.VoteTypeId
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.ParentId IN (SELECT Id FROM tag_posts)
  ),

  /* Total vote count per question */
  vote_counts AS (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM combined_votes
    GROUP BY PostId
  )

SELECT
  tp.Id,
  tp.Title,
  tp.Score,
  tp.AnswerCount,
  vs.UpVotes,
  vs.DownVotes,
  vs.NetScore,
  fe.FirstEditDate,
  (SELECT MIN(CreationDate) FROM Comments c WHERE c.PostId = tp.Id) AS FirstCommentDate,
  vcnt.TotalVotes,
  UPPER(SUBSTRING(tp.Tags FROM 5 FOR 3)) AS SampleTag,                           -- string expression
  (extract(epoch FROM (tp.CreationDate))/86400)::INT AS DaysSinceCreate,
  (extract(epoch FROM (COALESCE(tp.LastActivityDate, now())))/86400)::INT AS DaysSinceLastActivity,
  bc.Gold,
  bc.Silver,
  bc.Bronze,
  qus.OwnedSqlQuestions,
  qus.TotalQuestionScore,
  qus.RnkByReputation,
  qus.AllTags,
  COALESCE(qus.TotalQuestionScore, 0) + COALESCE(vs.NetScore, 0) AS CombinedScore,
  CASE WHEN qus.AllTags IS NULL THEN 'No tags' ELSE qus.AllTags END AS TagInfo
FROM tag_posts tp
LEFT JOIN first_edit fe ON fe.PostId = tp.Id
LEFT JOIN vote_sums vs ON vs.PostId = tp.Id
LEFT JOIN vote_counts vcnt ON vcnt.PostId = tp.Id
LEFT JOIN badge_counts bc ON bc.UserId = tp.OwnerUserId
LEFT JOIN question_user_stats qus ON qus.UserId = tp.OwnerUserId
ORDER BY tp.Score DESC, qus.RnkByReputation
LIMIT 200;
