-- {"query": "5863.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 849} 
WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
owner_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) AS total_questions_by_user,
    SUM(CASE WHEN r.rn_by_owner = 1 THEN 1 ELSE 0 END) AS top_question_escaped
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN ranked_questions r ON r.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    (SELECT COUNT(*) FROM Posts x WHERE x.OwnerUserId = p.OwnerUserId AND x.CreationDate >= p.CreationDate - INTERVAL '7 days') AS weekly_post_count
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_filters AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    v.TotalUp AS UpVotesSinceCreation,
    v.TotalDown AS DownVotesSinceCreation,
    CASE
      WHEN q.Score >= 10 THEN 'High'
      WHEN q.Score >= 0 THEN 'Medium'
      ELSE 'Low'
    END AS ScoreTier
  FROM ranked_questions q
  JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    WHERE CreationDate > (SELECT MIN(CreationDate) FROM Votes WHERE PostId = Votes.PostId)
    GROUP BY PostId
  ) v ON v.PostId = q.PostId
  WHERE q.rn_by_owner = 1
    AND q.ViewCount > 100
    AND q.CommentCount < 50
),
final_row AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerName,
    c.Reputation,
    c.CreationDate,
    c.LastActivityDate,
    c.ViewCount,
    c.Score,
    c.AnswerCount,
    c.FavoriteCount,
    c.ScoreTier,
    o.total_questions_by_user,
    o.top_question_escaped,
    r.weekly_post_count
  FROM complex_filters c
  LEFT JOIN owner_stats o ON o.UserId = c.OwnerUserId
  LEFT JOIN recent_activity r ON r.OwnerUserId = c.OwnerUserId AND r.PostId = c.PostId
)
SELECT
  PostId,
  Title,
  OwnerName,
  Reputation,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  AnswerCount,
  FavoriteCount,
  ScoreTier,
  total_questions_by_user,
  top_question_escaped,
  weekly_post_count
FROM final_row
ORDER BY LastActivityDate DESC
LIMIT 100;