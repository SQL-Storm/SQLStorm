-- {"query": "374.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 13430} 
WITH
q AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    COALESCE(p.ViewCount,0) AS ViewCount,
    p.AcceptedAnswerId,
    p.OwnerUserId,
    p.Tags,
    CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[] ELSE string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><') END AS tag_array,
    regexp_replace(COALESCE(p.Title,''), '\\s+', ' ', 'g') AS clean_title,
    length(COALESCE(p.Body,'')) AS body_len
  FROM Posts p
  WHERE p.PostTypeId = 1
),
a AS (
  SELECT
    p.Id,
    p.ParentId,
    p.CreationDate,
    p.Score,
    p.OwnerUserId,
    p.Body,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId = 2
),
q_ans AS (
  SELECT
    q.Id AS QuestionId,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AcceptedAnswerId,
    q.CreationDate AS QuestionCreation,
    COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL) AS AnswerCount,
    MAX(a.Score) AS MaxAnswerScore,
    AVG(a.Score)::numeric(10,3) AS AvgAnswerScore,
    SUM(CASE WHEN a.Score > q.Score THEN 1 ELSE 0 END) AS AnswersWithHigherScore,
    MIN(a.CreationDate) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS AcceptedAnswerCreation
  FROM q
  LEFT JOIN a ON a.ParentId = q.Id
  GROUP BY q.Id, q.Score, q.ViewCount, q.AcceptedAnswerId, q.CreationDate
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COALESCE(u.Views,0) AS ProfileViews,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS TotalPosts,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
    COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)),0)::numeric(10,3) AS AvgPostScore,
    MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS LastPostDate,
    u.CreationDate AS UserCreation,
    u.LastAccessDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation, u.Views, u.CreationDate, u.LastAccessDate
),
tag_flat AS (
  SELECT
    q.Id AS QuestionId,
    trim(t.tag) AS Tag
  FROM q
  CROSS JOIN LATERAL unnest(q.tag_array) AS t(tag)
),
tag_questions_ranked AS (
  SELECT
    tf.Tag,
    p.Id AS QuestionId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY tf.Tag ORDER BY COALESCE(p.Score,0) DESC, COALESCE(p.ViewCount,0) DESC, p.CreationDate DESC) AS rn
  FROM tag_flat tf
  JOIN Posts p ON p.Id = tf.QuestionId
  WHERE p.PostTypeId = 1
),
tag_aggregates AS (
  SELECT
    Tag,
    COUNT(QuestionId) AS QuestionCount,
    SUM(ViewCount) AS TotalViews,
    AVG(Score)::numeric(10,3) AS AvgQuestionScore,
    MAX(Score) AS MaxQuestionScore,
    MAX(CASE WHEN rn = 1 THEN QuestionId END) AS TopQuestionId
  FROM tag_questions_ranked
  GROUP BY Tag
),
tag_user_answers AS (
  SELECT
    tf.Tag,
    a.OwnerUserId,
    COUNT(a.Id) AS AnswersByUserToTag,
    AVG(a.Score)::numeric(10,3) AS AvgAnswerScoreToTag,
    SUM(CASE WHEN a.Score >= 0 THEN 1 ELSE 0 END) AS NonNegAnswers
  FROM tag_flat tf
  JOIN a ON a.ParentId = tf.QuestionId
  GROUP BY tf.Tag, a.OwnerUserId
),
top_answerers_per_tag AS (
  SELECT
    tua.Tag,
    tua.OwnerUserId AS UserId,
    COALESCE(u.Reputation,0) AS Reputation,
    tua.AnswersByUserToTag,
    tua.AvgAnswerScoreToTag,
    ROW_NUMBER() OVER (PARTITION BY tua.Tag ORDER BY tua.AnswersByUserToTag DESC, tua.AvgAnswerScoreToTag DESC NULLS LAST) AS rn
  FROM tag_user_answers tua
  LEFT JOIN Users u ON u.Id = tua.OwnerUserId
),
tag_pairs AS (
  SELECT
    tf1.Tag AS TagA,
    tf2.Tag AS TagB,
    COUNT(DISTINCT tf1.QuestionId) AS CoOccurrence,
    (COUNT(DISTINCT tf1.QuestionId)::numeric / NULLIF(LEAST(
       (SELECT COUNT(DISTINCT QuestionId) FROM tag_flat WHERE Tag = tf1.Tag),
       (SELECT COUNT(DISTINCT QuestionId) FROM tag_flat WHERE Tag = tf2.Tag)
     ),0))::numeric(10,3) AS CoRelScore
  FROM tag_flat tf1
  JOIN tag_flat tf2 ON tf1.QuestionId = tf2.QuestionId AND tf1.Tag < tf2.Tag
  GROUP BY tf1.Tag, tf2.Tag
  HAVING COUNT(DISTINCT tf1.QuestionId) > 5
),
recent_histories AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
),
recent_histories_top3 AS (
  SELECT rh.PostId, rh.HistoryId, rh.PostHistoryTypeId, rh.CreationDate, rh.UserId, rh.Comment, rh.Text
  FROM recent_histories rh
  WHERE rh.rn <= 3
),
badge_timing AS (
  SELECT
    b.UserId,
    MIN(b.Date) AS FirstBadgeDate,
    EXTRACT(EPOCH FROM (MIN(b.Date) - u.CreationDate))/86400.0 AS DaysToFirstBadge
  FROM Badges b
  JOIN Users u ON u.Id = b.UserId
  GROUP BY b.UserId, u.CreationDate
),
user_answer_leaderboard AS (
  SELECT
    us.UserId,
    us.Reputation,
    COALESCE(ua.AnswersPosted,0) AS AnswersPosted,
    us.AvgPostScore,
    ROW_NUMBER() OVER (ORDER BY COALESCE(ua.AnswersPosted,0) DESC, us.Reputation DESC) AS rn
  FROM user_stats us
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS AnswersPosted FROM Posts WHERE PostTypeId = 2 GROUP BY OwnerUserId
  ) ua ON ua.UserId = us.UserId
),
score_percentiles AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    NTILE(100) OVER (ORDER BY COALESCE(p.Score,0) DESC) AS ScorePercentile,
    NTILE(100) OVER (ORDER BY COALESCE(p.ViewCount,0) DESC) AS ViewPercentile
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
)
SELECT
  t.Tag,
  t.QuestionCount,
  t.TotalViews,
  t.AvgQuestionScore,
  t.MaxQuestionScore,
  q.Id AS TopQuestionId,
  q.Title AS TopQuestionTitle,
  q.Score AS TopQuestionScore,
  q.ViewCount AS TopQuestionViews,
  COALESCE((
    SELECT string_agg(
      COALESCE(u.DisplayName,'<anon>') || ' (' || COALESCE(tap.AnswersByUserToTag::text,'0') || ',avg=' || COALESCE(tap.AvgAnswerScoreToTag::text,'0') || ')',
      '; ' ORDER BY tap.AnswersByUserToTag DESC, tap.AvgAnswerScoreToTag DESC
    )
    FROM top_answerers_per_tag tap
    LEFT JOIN Users u ON u.Id = tap.UserId
    WHERE tap.Tag = t.Tag AND tap.rn <= 3
  ), '<none>') AS TopAnswerers,
  (SELECT tp.TagB FROM tag_pairs tp WHERE tp.TagA = t.Tag ORDER BY tp.CoOccurrence DESC LIMIT 1) AS MostCoOccurringTag,
  (t.TopQuestionId IS NOT NULL) AS HasTopQuestion,
  (COALESCE(t.MaxQuestionScore,0) * 0.6
   + COALESCE(t.TotalViews,0)::numeric / NULLIF(GREATEST(t.QuestionCount,1),1) * 0.0001
   + COALESCE((SELECT AVG(ua.AvgAnswerScoreToTag) FROM tag_user_answers ua WHERE ua.Tag = t.Tag),0) * 2
  )::numeric(12,6) AS ImpactCompositeScore,
  (SELECT COUNT(*) FROM tag_flat tf2 JOIN q_ans qa2 ON qa2.QuestionId = tf2.QuestionId
   WHERE tf2.Tag = t.Tag AND qa2.AnswerCount = 0
     AND qa2.QuestionScore >= (SELECT COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY QuestionScore) FROM q_ans))
  ) AS UnansweredHighScoreCount,
  CASE WHEN t.QuestionCount > 0 THEN
    (SELECT COUNT(*) FROM tag_flat tf2 JOIN q_ans qa2 ON qa2.QuestionId = tf2.QuestionId
     WHERE tf2.Tag = t.Tag AND qa2.AnswerCount = 0
       AND qa2.QuestionScore >= (SELECT COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY QuestionScore) FROM q_ans))
    )::numeric / NULLIF(t.QuestionCount,0)
  ELSE 0 END AS PercentUnansweredHighScore,
  COALESCE((SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = t.TopQuestionId AND ph.CreationDate >= now() - interval '180 days'),0) AS TopQuestionRecentEdits,
  lower(regexp_replace(t.Tag, '[^a-zA-Z0-9]+', '-', 'g')) AS TagSlug,
  CASE WHEN EXISTS (
    SELECT 1 FROM Posts p2 JOIN tag_flat tf3 ON p2.Id = tf3.QuestionId
    WHERE tf3.Tag = t.Tag AND p2.CreationDate >= now() - interval '30 days'
      AND (p2.Score >= (SELECT MIN(Score) FROM score_percentiles WHERE ScorePercentile <= 5)
           OR p2.ViewCount >= (SELECT MIN(ViewCount) FROM score_percentiles WHERE ViewPercentile <= 5))
  ) THEN true ELSE false END AS IsTrending,
  (SELECT string_agg(s, ' || ') FROM (
     SELECT substring(coalesce(ph.Comment,ph.Text)::text,1,140) AS s
     FROM PostHistory ph JOIN tag_flat tf4 ON ph.PostId = tf4.QuestionId
     WHERE tf4.Tag = t.Tag AND ph.CreationDate >= now() - interval '90 days'
     ORDER BY ph.CreationDate DESC
     LIMIT 10
  ) sub) AS RecentHistorySnippets,
  (SELECT COALESCE(u2.DisplayName,'<anon>') FROM Users u2 WHERE u2.Id = (
     SELECT ua.UserId FROM user_answer_leaderboard ua JOIN badge_timing bt ON ua.UserId = bt.UserId ORDER BY ua.AnswersPosted DESC LIMIT 1
  ) LIMIT 1) AS TopAnswererWithBadge,
  (SELECT AVG(bt.DaysToFirstBadge)::numeric(10,3) FROM badge_timing bt JOIN top_answerers_per_tag tap2 ON tap2.UserId = bt.UserId WHERE tap2.Tag = t.Tag AND tap2.rn <= 5) AS AvgDaysToFirstBadgeAmongTop5,
  (SELECT COALESCE(MAX(aua.AnswersByUserToTag)::numeric / NULLIF(SUM(aua.AnswersByUserToTag)::numeric,0),0)
   FROM tag_user_answers aua WHERE aua.Tag = t.Tag) AS TopContributorConcentration,
  CASE
    WHEN (COALESCE(t.MaxQuestionScore,0) > 50 OR COALESCE(t.TotalViews,0) > 50000) AND
         (EXISTS (SELECT 1 FROM tag_pairs tp WHERE tp.TagA = t.Tag AND tp.CoOccurrence > 100)) THEN 'Hot-Network'
    WHEN (COALESCE(t.QuestionCount,0) < 10 AND COALESCE(t.TotalViews,0) < 1000) THEN 'Cold'
    WHEN (IsTrending) THEN 'Trending'
    ELSE 'Stable'
  END AS TagState
FROM tag_aggregates t
LEFT JOIN Posts q ON q.Id = t.TopQuestionId
ORDER BY t.TotalViews DESC NULLS LAST, t.QuestionCount DESC
LIMIT 100;