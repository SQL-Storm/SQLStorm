-- {"query": "5666.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 911} 
WITH recent_questions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
tag_cross AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.ViewCount) AS MaxQuestionViews
  FROM Tags t
  JOIN Posts p ON t.Id = p.Tags::int  -- approximate tag linkage for benchmarking variety
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
activity_by_day AS (
  SELECT
    date_trunc('day', p.CreationDate) AS day,
    COUNT(*) AS questions_created,
    SUM(p.ViewCount) AS total_views,
    SUM(p.CommentCount) AS total_comments
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY date_trunc('day', p.CreationDate)
),
popular_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    RANK() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  WHERE u.Reputation > 1000
),
post_history_per_question AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS RevisionDate,
    ph.PostHistoryTypeId,
    ph.Comment
  FROM PostHistory ph
  JOIN Posts p ON ph.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND ph.CreationDate >= NOW() - INTERVAL '60 days'
),
outer_join_example AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.AnswerCount,
    COALESCE(vt.TotalUpVotes, 0) AS UpVotes,
    COALESCE(vt.TotalDownVotes, 0) AS DownVotes,
    COALESCE(vt.Accepted, false) AS IsAccepted
  FROM recent_questions q
  LEFT OUTER JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN BountyAmount ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN BountyAmount ELSE 0 END) AS TotalDownVotes,
      MAX(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS Accepted
    FROM Votes
    GROUP BY PostId
  ) vt ON vt.PostId = q.QuestionId
),
complex_filter AS (
  SELECT
    oq.QuestionId,
    oq.Title,
    oq.OwnerUserId,
    oq.CreationDate,
    oq.ViewCount,
    oq.AnswerCount,
    oq.UpVotes,
    oq.DownVotes,
    oq.IsAccepted,
    ROW_NUMBER() OVER (
      PARTITION BY oq.OwnerUserId
      ORDER BY oq.ViewCount DESC, oq.UpVotes DESC
    ) AS rn
  FROM outer_join_example oq
  WHERE (oq.ViewCount > 1000 OR oq.UpVotes > 10)
    AND (oq.IsAccepted = true OR oq.DownVotes = 0)
)
SELECT
  hh.QuestionId,
  hh.Title,
  hh.OwnerUserId,
  uu.DisplayName AS OwnerDisplayName,
  hh.CreationDate,
  hh.ViewCount,
  hh.AnswerCount,
  ah.AvgQuestionScore,
  ah.MaxQuestionViews,
  apd.day AS activityDay,
  apd.questions_created,
  apd.total_views,
  apd.total_comments,
  urep.rep_rank
FROM complex_filter hh
JOIN Users uu ON hh.OwnerUserId = uu.Id
LEFT JOIN tag_cross ah ON 1=1
LEFT JOIN activity_by_day apd ON apd.day = DATE(hh.CreationDate)
LEFT JOIN popular_users urep ON urep.UserId = hh.OwnerUserId
ORDER BY hh.ViewCount DESC
LIMIT 100;