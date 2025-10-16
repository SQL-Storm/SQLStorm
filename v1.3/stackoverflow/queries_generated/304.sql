-- {"query": "304.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19960} 
WITH
questions AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
),
q_tags AS (
  SELECT q.Id AS QuestionId,
         trim(t.tag) AS Tag
  FROM questions q
  CROSS JOIN LATERAL (
    SELECT unnest(
      CASE
        WHEN q.Tags IS NULL OR length(q.Tags) < 2 THEN ARRAY[]::text[]
        ELSE string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')
      END
    ) AS tag
  ) t
),
answers_agg AS (
  SELECT ParentId AS QuestionId,
         COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnswerCountActual,
         SUM(score) FILTER (WHERE PostTypeId = 2) AS SumAnswerScore,
         AVG(score) FILTER (WHERE PostTypeId = 2) AS AvgAnswerScore,
         MIN(CreationDate) FILTER (WHERE PostTypeId = 2) AS FirstAnswerAt,
         MAX(CreationDate) FILTER (WHERE PostTypeId = 2) AS LastAnswerAt
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY ParentId
),
accepted_answers AS (
  SELECT q.Id AS QuestionId, a.Id AS AcceptedAnswerId, a.CreationDate AS AcceptedAnswerAt, a.Score AS AcceptedAnswerScore
  FROM questions q
  JOIN Posts a ON q.AcceptedAnswerId = a.Id
  WHERE a.PostTypeId = 2
),
comments_agg AS (
  SELECT PostId,
         COUNT(*) AS CommentCountActual,
         COUNT(DISTINCT UserId) AS DistinctCommenters,
         MAX(CreationDate) AS LastCommentAt,
         MIN(CreationDate) AS FirstCommentAt,
         SUM(CASE WHEN UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
  FROM Comments
  GROUP BY PostId
),
history_agg AS (
  SELECT PostId,
         COUNT(*) AS EditCount,
         COUNT(*) FILTER (WHERE PostHistoryTypeId IN (4,5,6,2,3,24)) AS SignificantEdits,
         COUNT(DISTINCT UserId) AS DistinctEditors,
         MAX(CreationDate) AS LastEditAt,
         MIN(CreationDate) AS FirstEditAt,
         BOOL_OR(PostHistoryTypeId = 16) AS WasCommunityOwned
  FROM PostHistory
  GROUP BY PostId
),
votes_agg AS (
  SELECT PostId,
         COUNT(*) AS VoteCount,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN VoteTypeId IN (1,5) THEN 1 ELSE 0 END) AS OriginatorOrFavorite
  FROM Votes
  GROUP BY PostId
),
links_in AS (
  SELECT RelatedPostId AS QuestionId,
         COUNT(*) AS IncomingLinks,
         SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCountIn,
         SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCountIn
  FROM PostLinks
  GROUP BY RelatedPostId
),
links_out AS (
  SELECT PostId AS QuestionId,
         COUNT(*) AS OutgoingLinks,
         SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCountOut,
         SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCountOut
  FROM PostLinks
  GROUP BY PostId
),
user_badge_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreation,
         COUNT(b.Id) AS BadgeCount,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
tag_metrics AS (
  SELECT qt.Tag,
         COUNT(q.Id) AS TagQuestionCount,
         AVG(q.Score) AS AvgQuestionScore,
         COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY q.Score), 0)::numeric AS MedianQuestionScore,
         SUM(COALESCE(q.ViewCount,0)) AS TotalViews,
         AVG(COALESCE(q.AnswerCount,0)) AS AvgAnswerCountPerQuestion
  FROM q_tags qt
  JOIN questions q ON qt.QuestionId = q.Id
  GROUP BY qt.Tag
),
tag_question_rank AS (
  SELECT qt.QuestionId,
         qt.Tag,
         q.Score,
         RANK() OVER (PARTITION BY qt.Tag ORDER BY q.Score DESC NULLS LAST) AS TagRank,
         COUNT(*) OVER (PARTITION BY qt.Tag) AS TagTotalQuestions
  FROM q_tags qt
  JOIN questions q ON qt.QuestionId = q.Id
),
question_tag_rank_best AS (
  SELECT QuestionId,
         MIN(TagRank) AS BestTagRank,
         COUNT(*) AS TagCount,
         STRING_AGG(Tag, ',' ORDER BY Tag) AS TagList
  FROM tag_question_rank
  GROUP BY QuestionId
),
question_window AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount AS DeclaredAnswerCount,
         q.OwnerUserId,
         q.OwnerDisplayName,
         q.LastActivityDate,
         ROW_NUMBER() OVER (ORDER BY q.Score DESC NULLS LAST, q.ViewCount DESC NULLS LAST) AS GlobalRank,
         PERCENT_RANK() OVER (ORDER BY q.Score) AS ScorePercentRank
  FROM questions q
),
top_commenter_per_question AS (
  SELECT c.PostId AS QuestionId,
         c.UserId AS TopCommenterId,
         COALESCE(u.DisplayName, c.UserDisplayName) AS TopCommenterName,
         COUNT(*) AS TopCommentCount
  FROM Comments c
  LEFT JOIN Users u ON u.Id = c.UserId
  GROUP BY c.PostId, c.UserId, COALESCE(u.DisplayName, c.UserDisplayName)
),
top_commenter_best AS (
  SELECT DISTINCT ON (QuestionId) QuestionId, TopCommenterId, TopCommenterName, TopCommentCount
  FROM top_commenter_per_question
  ORDER BY QuestionId, TopCommentCount DESC NULLS LAST
),
top_editor_per_question AS (
  SELECT ph.PostId AS QuestionId,
         ph.UserId AS TopEditorId,
         COALESCE(ph.UserDisplayName, u.DisplayName) AS TopEditorName,
         COUNT(*) AS TopEditCount
  FROM PostHistory ph
  LEFT JOIN Users u ON u.Id = ph.UserId
  GROUP BY ph.PostId, ph.UserId, COALESCE(ph.UserDisplayName, u.DisplayName)
),
top_editor_best AS (
  SELECT DISTINCT ON (QuestionId) QuestionId, TopEditorId, TopEditorName, TopEditCount
  FROM top_editor_per_question
  ORDER BY QuestionId, TopEditCount DESC NULLS LAST
),
per_question_metrics AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.OwnerUserId,
         COALESCE(q.OwnerDisplayName, u.DisplayName, 'Community') AS EffectiveOwnerDisplayName,
         u.Reputation AS OwnerReputation,
         COALESCE(tbr.TagList, '') AS TagList,
         COALESCE(tbr.TagCount, 0) AS TagCount,
         COALESCE(aa.AnswerCountActual, 0) AS AnswerCountActual,
         COALESCE(aa.SumAnswerScore, 0) AS SumAnswerScore,
         COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
         COALESCE(EXTRACT(EPOCH FROM (aa.FirstAnswerAt - q.CreationDate))/3600.0, NULL) AS HoursToFirstAnswer,
         COALESCE(EXTRACT(EPOCH FROM (acc.AcceptedAnswerAt - q.CreationDate))/3600.0, NULL) AS HoursToAcceptedAnswer,
         COALESCE(ca.CommentCountActual, 0) AS CommentCount,
         COALESCE(ca.DistinctCommenters, 0) AS DistinctCommenters,
         COALESCE(hh.EditCount, 0) AS EditCount,
         COALESCE(hh.DistinctEditors, 0) AS DistinctEditors,
         COALESCE(vv.VoteCount, 0) AS VoteCount,
         COALESCE(vv.UpVotes, 0) AS UpVotes,
         COALESCE(vv.DownVotes, 0) AS DownVotes,
         COALESCE(li.DuplicateCountIn, 0) AS DuplicateCountIn,
         COALESCE(lo.DuplicateCountOut, 0) AS DuplicateCountOut,
         COALESCE(li.IncomingLinks, 0) AS IncomingLinks,
         COALESCE(lo.OutgoingLinks, 0) AS OutgoingLinks,
         qw.GlobalRank,
         qw.ScorePercentRank,
         COALESCE(q.Score, 0) AS QuestionScore,
         COALESCE(tbr.BestTagRank, NULL) AS BestTagRank,
         COALESCE(uub.GoldBadges,0) AS OwnerGoldBadges,
         COALESCE(uub.BadgeCount,0) AS OwnerBadgeCount,
         tcb.TopCommenterId,
         tcb.TopCommenterName,
         teb.TopEditorId,
         teb.TopEditorName
  FROM questions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN answers_agg aa ON aa.QuestionId = q.Id
  LEFT JOIN accepted_answers acc ON acc.QuestionId = q.Id
  LEFT JOIN comments_agg ca ON ca.PostId = q.Id
  LEFT JOIN history_agg hh ON hh.PostId = q.Id
  LEFT JOIN votes_agg vv ON vv.PostId = q.Id
  LEFT JOIN links_in li ON li.QuestionId = q.Id
  LEFT JOIN links_out lo ON lo.QuestionId = q.Id
  LEFT JOIN user_badge_stats uub ON uub.UserId = q.OwnerUserId
  LEFT JOIN question_window qw ON qw.QuestionId = q.Id
  LEFT JOIN question_tag_rank_best tbr ON tbr.QuestionId = q.Id
  LEFT JOIN top_commenter_best tcb ON tcb.QuestionId = q.Id
  LEFT JOIN top_editor_best teb ON teb.QuestionId = q.Id
),
engagement AS (
  SELECT pq.*,
         ((COALESCE(pq.QuestionScore,0)::numeric * 0.4)
          + (COALESCE(pq.AnswerCountActual,0)::numeric * 1.2)
          + (COALESCE(pq.CommentCount,0)::numeric * 0.5)
          + (GREATEST(LEAST(COALESCE(pq.OwnerReputation,0)::numeric/10000.0,1.0),0.0) * 5.0)
         ) AS EngagementRaw,
         (COALESCE(pq.ScorePercentRank,0) * 0.7
          + LEAST(COALESCE(pq.AnswerCountActual,0)::numeric / NULLIF(GREATEST(pq.TagCount,1),0), 10)::numeric * 0.3
         ) AS EngagementNormalized
  FROM per_question_metrics pq
),
is_hot AS (
  SELECT e.*,
         (e.EngagementRaw >= (SELECT COALESCE(percentile_cont(0.90) WITHIN GROUP (ORDER BY EngagementRaw), 0) FROM engagement)) AS IsHotFlag
  FROM engagement e
)
SELECT *
FROM (
  SELECT 'HOT'::text AS bucket,
         ih.QuestionId,
         substring(ih.Title FROM 1 FOR 150) AS TitleSnippet,
         ih.EffectiveOwnerDisplayName,
         ih.OwnerReputation,
         ih.TagList,
         ih.TagCount,
         ih.AnswerCountActual,
         ih.CommentCount,
         ih.EditCount,
         ih.VoteCount,
         ih.DuplicateCountIn,
         ih.DuplicateCountOut,
         ih.HoursToFirstAnswer,
         ih.HoursToAcceptedAnswer,
         ih.QuestionScore,
         ih.ScorePercentRank,
         ih.EngagementRaw,
         ih.EngagementNormalized,
         ih.IsHotFlag,
         ih.BestTagRank,
         ih.TopCommenterName,
         ih.TopEditorName
  FROM is_hot ih
  WHERE ih.IsHotFlag = TRUE
  ORDER BY ih.EngagementRaw DESC NULLS LAST
  LIMIT 200

  UNION ALL

  SELECT 'CONTROL'::text AS bucket,
         ih2.QuestionId,
         substring(ih2.Title FROM 1 FOR 150) AS TitleSnippet,
         ih2.EffectiveOwnerDisplayName,
         ih2.OwnerReputation,
         ih2.TagList,
         ih2.TagCount,
         ih2.AnswerCountActual,
         ih2.CommentCount,
         ih2.EditCount,
         ih2.VoteCount,
         ih2.DuplicateCountIn,
         ih2.DuplicateCountOut,
         ih2.HoursToFirstAnswer,
         ih2.HoursToAcceptedAnswer,
         ih2.QuestionScore,
         ih2.ScorePercentRank,
         ih2.EngagementRaw,
         ih2.EngagementNormalized,
         ih2.IsHotFlag,
         ih2.BestTagRank,
         ih2.TopCommenterName,
         ih2.TopEditorName
  FROM is_hot ih2
  WHERE ih2.IsHotFlag = FALSE
    AND ih2.QuestionId IN (SELECT QuestionId FROM is_hot WHERE IsHotFlag = FALSE ORDER BY random() LIMIT 200)
) AS combined
ORDER BY bucket, EngagementRaw DESC NULLS LAST
;