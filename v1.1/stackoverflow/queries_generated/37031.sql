-- {"query": "37031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2067} 
WITH
-- Recent active questions with tag arrays and computed ages
Questions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.CommentCount,0) AS CommentCount,
         CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[] ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END AS Tags,
         EXTRACT(EPOCH FROM (now() - p.CreationDate))/86400.0 AS AgeDays
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > now() - INTERVAL '3 years'
),
-- Answers joined to their parent question and enriched
Answers AS (
  SELECT a.Id, a.ParentId AS QuestionId, a.OwnerUserId, a.CreationDate, a.Score, a.CommentCount,
         CASE WHEN a.OwnerUserId IS NULL THEN -1 ELSE a.OwnerUserId END AS OwnerIdNormalized,
         EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToAnswer
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2
    AND q.PostTypeId = 1
    AND q.CreationDate > now() - INTERVAL '3 years'
),
-- User aggregates: reputation, tenure, activity recency
UserAgg AS (
  SELECT u.Id AS UserId, u.Reputation, u.CreationDate, u.DisplayName,
         EXTRACT(EPOCH FROM (now() - u.CreationDate))/86400.0 AS UserAgeDays,
         EXTRACT(EPOCH FROM (now() - u.LastAccessDate))/86400.0 AS DaysSinceLastAccess,
         COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionsPosted,
         COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswersPosted,
         COALESCE(MAX(p.LastActivityDate), u.CreationDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate
),
-- Tag popularity and quality metrics
TagMetrics AS (
  SELECT t.TagName,
         t.Count AS TagCount,
         COALESCE(tp.ExcerptPostId, tp.WikiPostId) AS RepresentativePostId,
         COALESCE(avg_q.AvgScore,0) AS AvgQuestionScore,
         COALESCE(avg_a.AvgAnswerScore,0) AS AvgAnswerScore,
         COALESCE(avg_ans.TimeToAnswerHrs, 0) AS AvgTimeToAnswerHrs
  FROM Tags t
  LEFT JOIN Posts tp ON tp.Id = t.ExcerptPostId OR tp.Id = t.WikiPostId
  LEFT JOIN (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag, AVG(p.Score) AS AvgScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
    GROUP BY 1
  ) avg_q ON avg_q.tag = t.TagName
  LEFT JOIN (
    SELECT tag, AVG(a.Score) AS AvgAnswerScore
    FROM (
      SELECT a.Score,
             unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2),'><')) AS tag
      FROM Posts a
      JOIN Posts q ON a.ParentId = q.Id
      WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
    ) sub
    GROUP BY tag
  ) avg_a ON avg_a.tag = t.TagName
  LEFT JOIN (
    SELECT tag, AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0) AS TimeToAnswerHrs
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
    GROUP BY tag
  ) avg_ans ON avg_ans.tag = t.TagName
),
-- Recent hot questions scoring combining multiple signals
HotScore AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.CommentCount,
         q.Tags,
         q.AgeDays,
         -- weighted signals: recency, score per day, view velocity, answers, comments, tag popularity boost
         (
           /* recency factor (recent favored) */
           GREATEST(0.1, 10.0 / NULLIF(q.AgeDays + 1.0,0))
           +
           /* engagement factor */
           (COALESCE(q.Score,0) * 2.0)
           +
           (LEAST(q.ViewCount, 1e6) / GREATEST(1.0, q.AgeDays) * 0.005)
           +
           (q.AnswerCount * 3.0)
           + (q.CommentCount * 1.0)
           +
           /* tag boost: average tag count inverse (rarer tags boost) */
           (SELECT COALESCE(SUM(LEAST(20.0, 1000.0/NULLIF(avg_tm.TagCount,1)) ),0)
            FROM unnest(q.Tags) AS t(tag)
            LEFT JOIN TagMetrics avg_tm ON avg_tm.TagName = t.tag)
         ) AS CompositeScore
  FROM Questions q
),
-- Consolidated per-question statistics with lateral subqueries for heavyweight operations
QuestionStats AS (
  SELECT h.QuestionId,
         h.Title,
         h.OwnerUserId,
         h.CreationDate,
         h.Score,
         h.ViewCount,
         h.AnswerCount,
         h.CommentCount,
         h.Tags,
         h.AgeDays,
         h.CompositeScore,
         -- top 3 answers by score and their authors' reputations
         a.top_answers,
         -- distinct commenters and commenter diversity
         c.commenter_count,
         c.top_commenters,
         -- whether accepted answer exists and its delta in score/time
         acc.accepted_answer_id,
         acc.accepted_answer_score,
         acc.hours_to_accepted,
         -- recent edits count and last editor reputation snapshot
         ph.revision_count,
         ph.last_editor_id,
         ph.last_editor_rep
  FROM HotScore h
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object('AnswerId', a.Id, 'Score', a.Score, 'OwnerId', a.OwnerUserId, 'HoursToAnswer', EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0) ORDER BY a.Score DESC, a.CreationDate ASC LIMIT 3) AS top_answers
    FROM Posts a
    JOIN Posts q ON q.Id = h.QuestionId
    WHERE a.ParentId = h.QuestionId AND a.PostTypeId = 2
  ) a ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT c.UserId) AS commenter_count,
           jsonb_agg(jsonb_build_object('UserId', c.UserId, 'Count', cnt) ORDER BY cnt DESC LIMIT 5) AS top_commenters
    FROM (
      SELECT c.UserId, COUNT(*) AS cnt
      FROM Comments c
      WHERE c.PostId = h.QuestionId
      GROUP BY c.UserId
    ) c
  ) c ON true
  LEFT JOIN LATERAL (
    SELECT p.AcceptedAnswerId AS accepted_answer_id,
           (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId) AS accepted_answer_score,
           CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN EXTRACT(EPOCH FROM ((SELECT CreationDate FROM Posts WHERE Id = p.AcceptedAnswerId) - p.CreationDate))/3600.0 ELSE NULL END AS hours_to_accepted
    FROM Posts p
    WHERE p.Id = h.QuestionId
  ) acc ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS revision_count,
           MAX(ph.UserId) AS last_editor_id,
           (SELECT Reputation FROM Users WHERE Id = MAX(ph.UserId))::int AS last_editor_rep
    FROM PostHistory ph
    WHERE ph.PostId = h.QuestionId
  ) ph ON true
),
-- Final aggregated leaderboard of hot questions with enrichments
Leaderboard AS (
  SELECT qs.QuestionId,
         qs.Title,
         qs.OwnerUserId,
         COALESCE(u.Reputation,0) AS OwnerReputation,
         qs.CompositeScore,
         qs.Score,
         qs.ViewCount,
         qs.AnswerCount,
         qs.CommentCount,
         qs.AgeDays,
         qs.top_answers,
         qs.commenter_count,
         qs.top_commenters,
         qs.accepted_answer_id,
         qs.accepted_answer_score,
         qs.hours_to_accepted,
         qs.revision_count,
         qs.last_editor_id,
         qs.last_editor_rep,
         -- normalize composite score by question age to surface bursty posts
         qs.CompositeScore / GREATEST(1.0, qs.AgeDays) AS Burstiness
  FROM QuestionStats qs
  LEFT JOIN Users u ON u.Id = qs.OwnerUserId
)
SELECT l.*
FROM Leaderboard l
ORDER BY l.Burstiness DESC NULLS LAST, l.CompositeScore DESC
LIMIT 200;