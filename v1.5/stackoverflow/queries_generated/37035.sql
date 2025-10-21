-- {"query": "37035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1991} 
WITH
-- recent activity window
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '365 days'
),
-- questions only
questions AS (
  SELECT *
  FROM recent_posts
  WHERE PostTypeId = 1
),
-- answers in the window, linked to questions
answers AS (
  SELECT p.*
  FROM recent_posts p
  WHERE PostTypeId = 2
),
-- tag explode: returns (PostId, tag) for questions
question_tags AS (
  SELECT q.Id AS QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, char_length(q.Tags)-2), '><')) AS Tag
  FROM questions q
  WHERE q.Tags IS NOT NULL AND q.Tags <> ''
),
-- aggregate per question: answer stats, comment counts, unique editors, last activity gap
question_stats AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount AS QuestionCommentCount,
    COALESCE(a.answer_count,0) AS AnswersFound,
    COALESCE(a.avg_answer_score,0) AS AvgAnswerScore,
    COALESCE(a.max_answer_score,0) AS MaxAnswerScore,
    COALESCE(a.accepted_answer_id, NULL) AS AcceptedAnswerId,
    COALESCE(e.editor_count,0) AS DistinctEditorCount,
    COALESCE(ph.revisions,0) AS RevisionCount,
    EXTRACT(EPOCH FROM (now() - q.LastActivityDate)) AS SecondsSinceLastActivity
  FROM questions q
  LEFT JOIN (
    SELECT ParentId,
           COUNT(*) AS answer_count,
           AVG(Score)::numeric(12,4) AS avg_answer_score,
           MAX(Score) AS max_answer_score,
           MAX(AcceptedAnswerId) FILTER (WHERE MAX(AcceptedAnswerId) IS NOT NULL) AS accepted_answer_id -- placeholder, will be NULL mostly
    FROM answers
    WHERE ParentId IS NOT NULL
    GROUP BY ParentId
  ) a ON a.ParentId = q.Id
  LEFT JOIN (
    SELECT PostId, COUNT(DISTINCT UserId) AS editor_count
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,24) -- edits/title/body/tags/suggested applied
      AND ph.CreationDate >= now() - interval '365 days'
    GROUP BY PostId
  ) e ON e.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS revisions
    FROM PostHistory ph
    WHERE ph.CreationDate >= now() - interval '365 days'
    GROUP BY PostId
  ) ph ON ph.PostId = q.Id
),
-- per-tag aggregates across questions
tag_aggregates AS (
  SELECT
    qt.Tag,
    COUNT(DISTINCT qt.QuestionId) AS QuestionsWithTag,
    SUM(qs.AnswersFound) AS TotalAnswers,
    AVG(NULLIF(qs.AnswersFound,0)) FILTER (WHERE qs.AnswersFound > 0) AS AvgAnswersPerAnsweredQuestion,
    AVG(qs.QuestionScore)::numeric(12,4) AS AvgQuestionScore,
    MAX(qs.MaxAnswerScore) AS TopAnswerScoreForTag,
    SUM(qs.RevisionCount) AS TotalRevisions,
    SUM(qs.DistinctEditorCount) AS TotalDistinctEditors,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qs.SecondsSinceLastActivity) AS MedianSecondsSinceLastActivity
  FROM question_tags qt
  JOIN question_stats qs ON qs.QuestionId = qt.QuestionId
  GROUP BY qt.Tag
),
-- hotness score: composite metric combining recency, score, activity, views, answers
tag_hotness AS (
  SELECT
    ta.Tag,
    ta.QuestionsWithTag,
    ta.TotalAnswers,
    ta.AvgAnswersPerAnsweredQuestion,
    ta.AvgQuestionScore,
    ta.TopAnswerScoreForTag,
    ta.TotalRevisions,
    ta.TotalDistinctEditors,
    ta.MedianSecondsSinceLastActivity,
    -- normalize components per tag using simple transforms
    ( (ta.QuestionsWithTag::numeric / NULLIF((SELECT MAX(QuestionsWithTag) FROM tag_aggregates),0)) * 0.25
      + ( COALESCE(ta.AvgQuestionScore,0) / NULLIF((SELECT MAX(AvgQuestionScore) FROM tag_aggregates),0) ) * 0.15
      + ( COALESCE(ta.TotalRevisions,0) / NULLIF((SELECT MAX(TotalRevisions) FROM tag_aggregates),0) ) * 0.20
      + ( COALESCE(ta.TotalAnswers,0) / NULLIF((SELECT MAX(TotalAnswers) FROM tag_aggregates),0) ) * 0.25
      + ( 1.0 - LEAST(1.0, COALESCE(ta.MedianSecondsSinceLastActivity,1) / NULLIF((SELECT MAX(MedianSecondsSinceLastActivity) FROM tag_aggregates),1)) ) * 0.15
    ) AS HotnessScore
  FROM tag_aggregates ta
),
-- user contribution stats for authors of questions in window
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT q.Id) FILTER (WHERE q.OwnerUserId = u.Id) AS QuestionsAuthored,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.OwnerUserId = u.Id) AS AnswersAuthored,
    SUM(COALESCE(p.Score,0)) FILTER (WHERE p.OwnerUserId = u.Id) AS TotalPostScore,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    MAX(u.Reputation) AS Reputation,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven -- approximate using Votes table
  FROM Users u
  LEFT JOIN questions q ON q.OwnerUserId = u.Id
  LEFT JOIN answers a ON a.OwnerUserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= now() - interval '365 days'
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= now() - interval '365 days'
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= now() - interval '365 days'
  GROUP BY u.Id, u.DisplayName
),
-- heavy join: find exemplar threads per hot tag: top questions by combined metric
tag_top_questions AS (
  SELECT
    th.Tag,
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    qs.QuestionScore,
    qs.AnswersFound,
    qs.AvgAnswerScore,
    qs.RevisionCount,
    ROW_NUMBER() OVER (PARTITION BY th.Tag ORDER BY ( (qs.QuestionScore::numeric * 0.4) + (COALESCE(qs.AvgAnswerScore,0) * 0.3) + (qs.AnswersFound * 0.2) + (qs.RevisionCount * 0.1) ) DESC, qs.SecondsSinceLastActivity ASC) AS rn
  FROM tag_hotness th
  JOIN question_tags qt ON qt.Tag = th.Tag
  JOIN question_stats qs ON qs.QuestionId = qt.QuestionId
  JOIN Posts q ON q.Id = qs.QuestionId
)
SELECT
  th.Tag,
  th.HotnessScore,
  th.QuestionsWithTag,
  th.TotalAnswers,
  th.AvgQuestionScore,
  th.TotalRevisions,
  tt.QuestionId AS TopQuestionId,
  tt.Title AS TopQuestionTitle,
  tt.CreationDate AS TopQuestionCreation,
  tt.OwnerUserId AS TopQuestionOwner,
  us.DisplayName AS TopQuestionOwnerName,
  us.QuestionsAuthored,
  us.AnswersAuthored,
  us.TotalPostScore,
  us.BadgesEarned,
  us.Reputation,
  -- compact JSON-like aggregates for quick ingestion by benchmarking clients
  json_build_object(
    'tag_metrics', json_build_object(
       'questions_with_tag', th.QuestionsWithTag,
       'total_answers', th.TotalAnswers,
       'avg_question_score', th.AvgQuestionScore,
       'total_revisions', th.TotalRevisions,
       'median_seconds_since_last_activity', th.MedianSecondsSinceLastActivity
    ),
    'top_question', json_build_object(
       'id', tt.QuestionId,
       'title', tt.Title,
       'creation_date', tt.CreationDate,
       'owner_user_id', tt.OwnerUserId
    ),
    'owner', json_build_object(
       'id', us.UserId,
       'display_name', us.DisplayName,
       'reputation', us.Reputation,
       'badges_earned_last_year', us.BadgesEarned
    )
  ) AS Payload
FROM tag_hotness th
LEFT JOIN tag_top_questions tt ON tt.Tag = th.Tag AND tt.rn = 1
LEFT JOIN user_stats us ON us.UserId = tt.OwnerUserId
ORDER BY th.HotnessScore DESC NULLS LAST
LIMIT 100;