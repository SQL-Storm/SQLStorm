-- {"query": "335.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16445} 
WITH
  a AS (
    SELECT p.Id, p.ParentId, p.OwnerUserId AS AnswererId, p.CreationDate AS AnswerCreationDate, p.Score AS AnswerScore, p.CommentCount AS AnswerCommentCount
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  answer_ranks AS (
    SELECT a.*,
           row_number() OVER (PARTITION BY a.ParentId ORDER BY a.AnswerScore DESC NULLS LAST, a.AnswerCreationDate ASC) AS rn_score,
           rank() OVER (PARTITION BY a.ParentId ORDER BY a.AnswerScore DESC NULLS LAST) as rnk_score,
           dense_rank() OVER (PARTITION BY a.ParentId ORDER BY a.AnswerScore DESC NULLS LAST) as dense_rnk
    FROM a
  ),
  answer_agg AS (
    SELECT ParentId AS QuestionId,
           count(*) FILTER (WHERE AnswerScore IS NOT NULL) AS AnswersHavingScore,
           count(*) AS TotalAnswers,
           sum(AnswerScore) AS SumAnswerScore,
           avg(AnswerScore::numeric) AS AvgAnswerScore,
           max(AnswerScore) as MaxAnswerScore,
           min(AnswerCreationDate) as FirstAnswerDate,
           max(AnswerCreationDate) as LastAnswerDate,
           sum(case when AnswerScore >= 5 then 1 else 0 end) as HighScoringAnswers
    FROM a
    GROUP BY ParentId
  ),
  comments_per_post AS (
    SELECT PostId,
           count(*) as CommentsOnPost,
           count(distinct UserId) as DistinctCommenters
    FROM Comments
    GROUP BY PostId
  ),
  badge_summary AS (
    SELECT UserId,
           count(*) as BadgesTotal,
           sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
           sum(case when TagBased = B'1' then 1 else 0 end) as TagBasedBadges
    FROM Badges
    GROUP BY UserId
  ),
  tags_exploded AS (
    SELECT q.Id as QuestionId,
           lower(trim(t.tag))::varchar(35) as Tag
    FROM Posts q
    CROSS JOIN LATERAL (
      SELECT unnest(string_to_array(substring(q.Tags, 2, char_length(q.Tags) - 2), '><')) as tag
    ) t
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND char_length(q.Tags) > 2
  ),
  tag_stats AS (
    SELECT te.Tag,
           count(distinct te.QuestionId) as QuestionCount,
           avg(coalesce(q.ViewCount,0)) as AvgViews,
           sum(coalesce(q.AnswerCount,0)) as SumAnswers,
           max(coalesce(q.Score,0)) as MaxQuestionScore,
           percentile_cont(0.5) within group (order by coalesce(q.Score,0)) as MedianScore
    FROM tags_exploded te
    JOIN Posts q ON q.Id = te.QuestionId
    GROUP BY te.Tag
  ),
  posthistory_counts AS (
    SELECT PostId,
           count(*) as PH_Count,
           count(*) FILTER (WHERE PostHistoryTypeId = 5) as BodyEdits,
           count(*) FILTER (WHERE PostHistoryTypeId = 4) as TitleEdits,
           bool_or(PostHistoryTypeId = 10) as EverClosed
    FROM PostHistory
    GROUP BY PostId
  ),
  user_post_stats AS (
    SELECT u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           count(p.Id) FILTER (WHERE p.PostTypeId = 1) as NumQuestions,
           count(p.Id) FILTER (WHERE p.PostTypeId = 2) as NumAnswers,
           count(distinct p.Id) as NumPosts,
           avg(p.Score) FILTER (WHERE p.Score IS NOT NULL) as AvgPostScore,
           max(p.CreationDate) as LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  heavy_questions AS (
    SELECT q.Id,
           q.Title,
           q.CreationDate,
           q.OwnerUserId,
           q.Score,
           q.ViewCount,
           q.Tags,
           q.AcceptedAnswerId,
           q.AnswerCount,
           q.CommentCount,
           q.FavoriteCount,
           q.LastActivityDate,
           q.ClosedDate,
           coalesce(a_agg.TotalAnswers,0) as TotalAnswers,
           a_agg.AvgAnswerScore,
           a_agg.MaxAnswerScore,
           coalesce(cp.CommentsOnPost,0) as QuestionComments,
           coalesce(pb.PH_Count,0) as HistoryEdits,
           coalesce(bad.BadgesTotal,0) as OwnerBadgeCount,
           coalesce(ups.NumAnswers,0) as OwnerNumAnswers,
           coalesce(ups.NumQuestions,0) as OwnerNumQuestions,
           coalesce(dup_counts.DuplicateOutCount, 0) as DuplicateOutCount,
           (SELECT count(distinct a2.OwnerUserId) FROM Posts a2 WHERE a2.PostTypeId = 2 AND a2.ParentId = q.Id) as DistinctAnswerers,
           (
             SELECT count(distinct coalesce(cu.UserId, -1))
             FROM Comments cu
             WHERE cu.PostId = q.Id
                OR cu.PostId IN (SELECT a3.Id FROM Posts a3 WHERE a3.ParentId = q.Id)
           ) as DistinctCommentersAll,
           (
             SELECT extract(epoch from (aa.CreationDate - q.CreationDate))
             FROM Posts aa
             WHERE aa.Id = q.AcceptedAnswerId
           ) as SecondsToAccepted,
           (
             SELECT count(*) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (10,11)
           ) as CloseOpenEvents
    FROM Posts q
    LEFT JOIN answer_agg a_agg ON a_agg.QuestionId = q.Id
    LEFT JOIN comments_per_post cp ON cp.PostId = q.Id
    LEFT JOIN posthistory_counts pb ON pb.PostId = q.Id
    LEFT JOIN badge_summary bad ON bad.UserId = q.OwnerUserId
    LEFT JOIN user_post_stats ups ON ups.UserId = q.OwnerUserId
    LEFT JOIN (
      SELECT pl.PostId, count(*) as DuplicateOutCount
      FROM PostLinks pl
      WHERE pl.LinkTypeId = 3
      GROUP BY pl.PostId
    ) dup_counts ON dup_counts.PostId = q.Id
    WHERE q.PostTypeId = 1
  ),
  tag_question_ranks AS (
    SELECT te.Tag, hq.Id as QuestionId, hq.Title, hq.Score, hq.ViewCount,
           row_number() OVER (PARTITION BY te.Tag ORDER BY hq.Score DESC NULLS LAST, hq.ViewCount DESC NULLS LAST) as TagRankByScore,
           dense_rank() OVER (PARTITION BY te.Tag ORDER BY hq.Score DESC NULLS LAST) as TagDenseRank,
           rank() OVER (PARTITION BY te.Tag ORDER BY hq.ViewCount DESC NULLS LAST) as TagRankByViews
    FROM tags_exploded te
    JOIN Posts hq ON hq.Id = te.QuestionId AND hq.PostTypeId = 1
    LEFT JOIN heavy_questions hq2 ON hq2.Id = hq.Id
  ),
  tag_combinations AS (
    SELECT a.Tag as TagA, b.Tag as TagB, count(*) as Cooccurrence
    FROM tags_exploded a
    JOIN tags_exploded b ON a.QuestionId = b.QuestionId AND a.Tag < b.Tag
    GROUP BY a.Tag, b.Tag
  ),
  co_tag_top AS (
    SELECT TagA, TagB, Cooccurrence,
           dense_rank() OVER (PARTITION BY TagA ORDER BY Cooccurrence DESC) as CoRank
    FROM tag_combinations
  ),
  final_questions AS (
    SELECT
      hq.Id::varchar as EntityId,
      'QUESTION'::varchar as EntityType,
      coalesce(hq.Title,'') as Name,
      hq.OwnerUserId as OwnerUserId,
      coalesce(hq.OwnerBadgeCount,0)::int as OwnerBadgeCount,
      coalesce(hq.TotalAnswers,0)::int as TotalAnswers,
      coalesce(hq.AnswerCount,0)::int as DeclaredAnswerCount,
      coalesce(hq.AvgAnswerScore,0)::numeric as AvgAnswerScore,
      coalesce(hq.QuestionComments,0)::int as QuestionComments,
      coalesce(hq.DistinctAnswerers,0)::int as DistinctAnswerers,
      coalesce(hq.DistinctCommentersAll,0)::int as DistinctCommentersAll,
      coalesce(hq.SecondsToAccepted,NULL)::numeric as SecondsToAccepted,
      coalesce(hq.HistoryEdits,0)::int as Edits,
      coalesce(hq.Score,0)::int as Score,
      coalesce(hq.ViewCount,0)::int as ViewCount,
      (coalesce(hq.Score::numeric,0) / NULLIF(coalesce(hq.ViewCount,0)::numeric,0)) as ScorePerView,
      ((hq.FavoriteCount * 1.0) + coalesce(hq.OwnerBadgeCount,0) * 0.1) as PopularityIndex,
      trim(coalesce(hq.Title,'')) || ' :: ' || coalesce((SELECT tag FROM tags_exploded te2 WHERE te2.QuestionId = hq.Id LIMIT 1), 'no-tag') as TinySummary,
      row_number() OVER (ORDER BY coalesce(hq.Score,0) DESC, coalesce(hq.ViewCount,0) DESC) as GlobalOrTagRank
    FROM heavy_questions hq
    WHERE hq.Score IS NOT NULL
  ),
  final_tags AS (
    SELECT
      ts.Tag::varchar as EntityId,
      'TAG'::varchar as EntityType,
      ts.Tag::varchar as Name,
      NULL::int as OwnerUserId,
      0::int as OwnerBadgeCount,
      COALESCE(ts.SumAnswers,0)::int as TotalAnswers,
      COALESCE(ts.QuestionCount,0)::int as DeclaredAnswerCount,
      NULL::numeric as AvgAnswerScore,
      0::int as QuestionComments,
      (
        SELECT count(distinct a.OwnerUserId)
        FROM Posts a
        JOIN tags_exploded te2 ON te2.QuestionId = a.ParentId
        WHERE a.PostTypeId = 2 AND te2.Tag = ts.Tag
      )::int as DistinctAnswerers,
      (
        SELECT count(distinct coalesce(c.UserId,-1))
        FROM Comments c
        JOIN Posts p ON p.Id = c.PostId
        JOIN tags_exploded te3 ON te3.QuestionId = p.Id OR te3.QuestionId = p.ParentId
        WHERE te3.Tag = ts.Tag
      )::int as DistinctCommentersAll,
      NULL::numeric as SecondsToAccepted,
      COALESCE( (SELECT avg(ph.PH_Count::numeric) FROM posthistory_counts ph JOIN tags_exploded te4 ON ph.PostId = te4.QuestionId WHERE te4.Tag = ts.Tag), 0)::int as Edits,
      COALESCE(ts.MaxQuestionScore,0)::int as Score,
      COALESCE(ts.AvgViews,0)::int as ViewCount,
      (COALESCE(ts.MaxQuestionScore,0)::numeric / NULLIF(COALESCE(ts.AvgViews,0)::numeric,0)) as ScorePerView,
      (COALESCE(ts.QuestionCount,0)::numeric * COALESCE(ts.AvgViews,0)::numeric) / NULLIF(COALESCE(ts.MedianScore,1),0) as PopularityIndex,
      COALESCE( (SELECT string_agg(ct.TagB, ',') FROM (SELECT TagB FROM co_tag_top c WHERE c.TagA = ts.Tag AND c.CoRank <= 3 ORDER BY c.Cooccurrence DESC NULLS LAST) ct), '') as TinySummary,
      rank() OVER (ORDER BY ts.QuestionCount DESC, ts.AvgViews DESC) as GlobalOrTagRank
    FROM tag_stats ts
  )
SELECT * FROM final_questions
UNION ALL
SELECT * FROM final_tags
ORDER BY EntityType, GlobalOrTagRank
LIMIT 250;