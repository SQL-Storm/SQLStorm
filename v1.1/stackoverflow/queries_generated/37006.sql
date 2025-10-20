-- {"query": "37006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1498} 
WITH recent_questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.ViewCount, p.Score, p.Tags,
         regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '1 year'
),
answer_stats AS (
  SELECT a.ParentId AS QuestionId,
         count(*) FILTER (WHERE a.Score > 0) AS PositiveAnswers,
         count(*) FILTER (WHERE a.Score = 0) AS ZeroAnswers,
         count(*) FILTER (WHERE a.Score < 0) AS NegativeAnswers,
         avg(a.Score) AS AvgAnswerScore,
         max(a.Score) AS MaxAnswerScore,
         min(a.Score) AS MinAnswerScore,
         count(*) AS AnswerCount
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
user_activity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreation,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
         count(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
         count(b.Id) AS BadgesWon,
         max(p.CreationDate) FILTER (WHERE p.OwnerUserId = u.Id) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
tag_popularity AS (
  SELECT t.TagName,
         t.Id AS TagId,
         t.Count AS TotalTaggedQuestions,
         coalesce(sum(rq.ViewCount),0) AS ViewsLastYear,
         coalesce(avg(rq.Score),0) AS AvgScoreLastYear,
         coalesce(sum(as_.AnswerCount),0) AS AnswersLastYear,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY rq.Score) AS MedianScoreLastYear
  FROM Tags t
  LEFT JOIN recent_questions rq ON rq.Tag = t.TagName
  LEFT JOIN answer_stats as_ ON as_.QuestionId = rq.Id
  GROUP BY t.Id, t.TagName, t.Count
),
duplicate_graph AS (
  SELECT pl.PostId AS SourceQuestion, pl.RelatedPostId AS TargetQuestion, lt.Name AS LinkType
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.PostId IN (SELECT Id FROM recent_questions)
    AND pl.RelatedPostId IN (SELECT Id FROM recent_questions)
),
hot_questions AS (
  SELECT rq.Id, rq.Title, rq.OwnerUserId, rq.CreationDate, rq.ViewCount, rq.Score,
         COALESCE(a.AnswerCount,0) AS AnswerCount,
         COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
         u.DisplayName AS OwnerName,
         row_number() OVER (PARTITION BY regexp_split_to_table(substring(rq.Tags,2,length(rq.Tags)-2), '><') ORDER BY (rq.ViewCount * 0.6 + rq.Score * 5 + COALESCE(a.AnswerCount,0) * 10) DESC) AS TagRank
  FROM recent_questions rq
  LEFT JOIN answer_stats a ON a.QuestionId = rq.Id
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
),
tag_top_summary AS (
  SELECT tp.TagName,
         tp.TotalTaggedQuestions,
         tp.ViewsLastYear,
         tp.AvgScoreLastYear,
         tp.AnswersLastYear,
         tp.MedianScoreLastYear,
         ht.Id AS HotQuestionId,
         ht.Title AS HotQuestionTitle,
         ht.OwnerName AS HotQuestionOwner,
         ht.ViewCount AS HotQuestionViews,
         ht.Score AS HotQuestionScore
  FROM tag_popularity tp
  LEFT JOIN LATERAL (
    SELECT hq.*
    FROM hot_questions hq
    WHERE regexp_split_to_table(substring(hq.Tags,2,length(hq.Tags)-2), '><') = tp.TagName
    ORDER BY (hq.ViewCount * 0.6 + hq.Score * 5 + hq.AnswerCount * 10) DESC
    LIMIT 1
  ) ht ON true
),
complex_metrics AS (
  SELECT tt.TagName,
         tt.TotalTaggedQuestions,
         tt.ViewsLastYear,
         tt.AvgScoreLastYear,
         tt.AnswersLastYear,
         tt.MedianScoreLastYear,
         tt.HotQuestionId,
         tt.HotQuestionTitle,
         tt.HotQuestionOwner,
         tt.HotQuestionViews,
         tt.HotQuestionScore,
         count(distinct dg.SourceQuestion) FILTER (WHERE dg.LinkType = 'Duplicate') AS DuplicateLinksFromHotYear,
         count(distinct dg.TargetQuestion) FILTER (WHERE dg.LinkType = 'Duplicate') AS DuplicateLinksToHotYear,
         (tt.ViewsLastYear::float / NULLIF(tt.TotalTaggedQuestions,0)) AS AvgViewsPerTagQuestion,
         (tt.AnswersLastYear::float / NULLIF(tt.ViewsLastYear,0)) AS AnswersPerView,
         (tt.MedianScoreLastYear - tt.AvgScoreLastYear) AS MedianMinusAvgScore
  FROM tag_top_summary tt
  LEFT JOIN duplicate_graph dg ON (dg.SourceQuestion = tt.HotQuestionId OR dg.TargetQuestion = tt.HotQuestionId)
  GROUP BY tt.TagName, tt.TotalTaggedQuestions, tt.ViewsLastYear, tt.AvgScoreLastYear, tt.AnswersLastYear, tt.MedianScoreLastYear, tt.HotQuestionId, tt.HotQuestionTitle, tt.HotQuestionOwner, tt.HotQuestionViews, tt.HotQuestionScore
)
SELECT cm.TagName,
       cm.TotalTaggedQuestions,
       cm.ViewsLastYear,
       cm.AvgScoreLastYear,
       round(cm.MedianScoreLastYear::numeric,3) AS MedianScoreLastYear,
       cm.AnswersLastYear,
       round(cm.AvgViewsPerTagQuestion::numeric,3) AS AvgViewsPerTagQuestion,
       round(cm.AnswersPerView::numeric,6) AS AnswersPerView,
       cm.MedianMinusAvgScore,
       cm.DuplicateLinksFromHotYear,
       cm.DuplicateLinksToHotYear,
       cm.HotQuestionId,
       cm.HotQuestionTitle,
       cm.HotQuestionOwner,
       cm.HotQuestionViews,
       cm.HotQuestionScore
FROM complex_metrics cm
WHERE cm.TotalTaggedQuestions > 100
  AND cm.ViewsLastYear > 10000
ORDER BY (cm.HotQuestionViews * 0.5 + cm.ViewsLastYear * 0.2 + cm.AnswersLastYear * 0.3) DESC
LIMIT 50;