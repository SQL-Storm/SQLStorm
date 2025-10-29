-- {"query": "50.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4157} 
with
-- Normalize tags into rows for questions
question_tags as (
  select
    p.Id as QuestionId,
    lower(trim(t)) as TagName
  from Posts p
  cross join lateral unnest(
    case
      when p.PostTypeId = 1 and p.Tags is not null and length(p.Tags) >= 2
      then string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t
  where p.PostTypeId = 1
),
-- Derive per-user activity bands and recency metrics
user_activity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
    date_part('year', age(u.LastAccessDate, u.CreationDate)) as YearsActive,
    case
      when u.Reputation >= 100000 then 'Legend'
      when u.Reputation >= 20000 then 'Veteran'
      when u.Reputation >= 3000 then 'Established'
      when u.Reputation >= 500 then 'Contributor'
      else 'Newbie'
    end as RepBand,
    -- Guard against negatives if clocks skewed
    greatest(extract(epoch from (u.LastAccessDate - u.CreationDate)) / 86400.0, 0) as DaysBetweenFirstAndLastSeen
  from Users u
),
-- Aggregate badges per user with pivoted counts and first/last badge dates
badge_agg as (
  select
    b.UserId,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
    sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges,
    min(b.Date) as FirstBadgeAt,
    max(b.Date) as LastBadgeAt
  from Badges b
  group by b.UserId
),
-- Question level aggregates including tag diversity and engagement
question_agg as (
  select
    q.Id as QuestionId,
    q.OwnerUserId as AskerId,
    q.CreationDate as AskedAt,
    q.Score as QuestionScore,
    q.ViewCount,
    q.FavoriteCount,
    q.AnswerCount,
    count(distinct qt.TagName) as TagDiversity,
    string_agg(distinct qt.TagName, ',' order by qt.TagName) as TagsCsv,
    -- Recency buckets for closed/reopened history and protection
    bool_or(ph_closed.PostId is not null) as WasEverClosed,
    bool_or(ph_reopened.PostId is not null) as WasEverReopened,
    bool_or(ph_protected.PostId is not null) as WasEverProtected
  from Posts q
  left join question_tags qt on qt.QuestionId = q.Id
  left join lateral (
    select 1 as PostId
    from PostHistory ph
    where ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    limit 1
  ) ph_closed on true
  left join lateral (
    select 1 as PostId
    from PostHistory ph
    where ph.PostId = q.Id and ph.PostHistoryTypeId = 11
    limit 1
  ) ph_reopened on true
  left join lateral (
    select 1 as PostId
    from PostHistory ph
    where ph.PostId = q.Id and ph.PostHistoryTypeId = 19
    limit 1
  ) ph_protected on true
  where q.PostTypeId = 1
  group by q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.FavoriteCount, q.AnswerCount
),
-- Answer aggregates per question, including accepted answer markers and score distribution
answer_agg as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerTotal,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedCount,
    max(a.Score) as MaxAnswerScore,
    avg(a.Score::numeric) as AvgAnswerScore,
    sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
    sum(case when a.Score < 0 then 1 else 0 end) as NegativeAnswers,
    min(a.CreationDate) as FirstAnswerAt,
    max(a.CreationDate) as LastAnswerAt
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
  group by a.ParentId
),
-- Votes and favorites per question separated to highlight activity shape
vote_agg as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesLegacy,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountySum
  from Votes v
  group by v.PostId
),
-- Link structure: duplicates and related links counts and earliest link time
link_agg as (
  select
    pl.PostId as QuestionId,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as RelatedLinks,
    min(pl.CreationDate) as FirstLinkAt
  from PostLinks pl
  group by pl.PostId
),
-- Comment activity summarized per question and by top commenter
comment_agg as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    sum(coalesce(c.Score,0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
-- Per-user post contributions split by type
user_post_agg as (
  select
    p.OwnerUserId as UserId,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsAuthored,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersAuthored,
    sum(case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAccepted,
    sum(case when p.PostTypeId = 2 and exists (select 1 from Posts q where q.Id = p.ParentId and q.AcceptedAnswerId = p.Id) then 1 else 0 end) as AcceptedAnswersAuthored,
    sum(coalesce(p.Score,0)) as TotalPostScore,
    max(p.LastActivityDate) as LastPostActivityAt
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
-- Build a working set of moderately popular questions in varied tag sets
candidate_questions as (
  select
    qa.QuestionId,
    qa.AskerId,
    qa.AskedAt,
    qa.QuestionScore,
    qa.ViewCount,
    qa.FavoriteCount,
    qa.AnswerCount,
    qa.TagDiversity,
    qa.TagsCsv,
    qa.WasEverClosed,
    qa.WasEverReopened,
    qa.WasEverProtected
  from question_agg qa
  where
    -- Reasonably popular or controversial
    (qa.ViewCount >= 1000 or qa.QuestionScore between -2 and 2)
    and coalesce(qa.TagDiversity,0) between 1 and 5
),
-- Rank users by a composite performance score using window functions
user_rankings as (
  select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.RepBand,
    ua.YearsActive,
    ba.BadgeCount,
    coalesce(ba.GoldCount,0) as GoldCount,
    coalesce(ba.SilverCount,0) as SilverCount,
    coalesce(ba.BronzeCount,0) as BronzeCount,
    upa.QuestionsAuthored,
    upa.AnswersAuthored,
    upa.AcceptedAnswersAuthored,
    upa.QuestionsWithAccepted,
    upa.TotalPostScore,
    ua.LocationNorm,
    -- Composite score weighting reputation, gold badges, accepted answers, and recency
    (
      ua.Reputation * 0.0025
      + coalesce(ba.GoldCount,0) * 3.0
      + coalesce(upa.AcceptedAnswersAuthored,0) * 1.25
      + coalesce(upa.TotalPostScore,0) * 0.01
      + least(coalesce(extract(epoch from (now() - upa.LastPostActivityAt)) / 86400.0, 3650), 3650) * -0.001
    ) as PerfScore,
    row_number() over (
      partition by ua.LocationNorm
      order by
        (
          ua.Reputation * 0.0025
          + coalesce(ba.GoldCount,0) * 3.0
          + coalesce(upa.AcceptedAnswersAuthored,0) * 1.25
          + coalesce(upa.TotalPostScore,0) * 0.01
          + least(coalesce(extract(epoch from (now() - upa.LastPostActivityAt)) / 86400.0, 3650), 3650) * -0.001
        ) desc nulls last,
        ua.UserId
    ) as RankInLocation
  from user_activity ua
  left join badge_agg ba on ba.UserId = ua.UserId
  left join user_post_agg upa on upa.UserId = ua.UserId
),
-- Correlate candidate questions with asker and top answerer characteristics
question_user_join as (
  select
    cq.*,
    ur.DisplayName as AskerName,
    ur.RepBand as AskerRepBand,
    ur.PerfScore as AskerPerfScore,
    ur.RankInLocation as AskerRankInLoc,
    ur.LocationNorm as AskerLocation,
    aa.AnswerTotal,
    aa.AcceptedCount,
    aa.MaxAnswerScore,
    aa.AvgAnswerScore,
    aa.PositiveAnswers,
    aa.NegativeAnswers,
    va.UpVotes,
    va.DownVotes,
    coalesce(va.FavoritesLegacy, 0) + coalesce(cq.FavoriteCount, 0) as FavoriteCombined,
    va.BountySum,
    la.DuplicateLinks,
    la.RelatedLinks,
    ca.CommentCount,
    ca.CommentScoreSum,
    la.FirstLinkAt,
    ca.LastCommentAt
  from candidate_questions cq
  left join user_rankings ur on ur.UserId = cq.AskerId
  left join answer_agg aa on aa.QuestionId = cq.QuestionId
  left join vote_agg va on va.QuestionId = cq.QuestionId
  left join link_agg la on la.QuestionId = cq.QuestionId
  left join comment_agg ca on ca.QuestionId = cq.QuestionId
),
-- Compute per-question engagement velocity and controversy indicators
question_metrics as (
  select
    quj.*,
    -- Engagement velocity proxies
    case
      when quj.AnswerTotal > 0 and quj.FirstLinkAt is not null
        then extract(epoch from (quj.FirstLinkAt - quj.AskedAt)) / greatest(quj.AnswerTotal,1)
      else null
    end as SecsPerAnswerUntilFirstLink,
    case
      when quj.LastCommentAt is not null
        then extract(epoch from (quj.LastCommentAt - quj.AskedAt)) / 3600.0
      else null
    end as HoursUntilLastComment,
    -- Controversy: high comments + mixed votes + reopen/close churn
    (
      coalesce(quj.CommentCount,0) >= 10
      and coalesce(quj.UpVotes,0) >= 5
      and coalesce(quj.DownVotes,0) >= 3
      and (quj.WasEverClosed or quj.WasEverReopened)
    ) as IsControversial,
    -- Quality proxy
    (
      coalesce(quj.AcceptedCount,0) = 1
      and coalesce(quj.MaxAnswerScore,0) >= 2
      and coalesce(quj.QuestionScore,0) >= 1
    ) as HasStrongAnswer
  from question_user_join quj
),
-- Window stats across tags to enable comparative ranking
tag_level as (
  select
    qm.QuestionId,
    t.TagName,
    qm.QuestionScore,
    qm.ViewCount,
    qm.FavoriteCombined,
    qm.AcceptedCount,
    avg(qm.QuestionScore) over (partition by t.TagName) as AvgScoreByTag,
    percentile_cont(0.9) within group (order by qm.ViewCount) over (partition by t.TagName) as P90ViewsByTag,
    rank() over (partition by t.TagName order by coalesce(qm.FavoriteCombined,0) desc, qm.ViewCount desc) as FavRankInTag
  from question_metrics qm
  join question_tags t on t.QuestionId = qm.QuestionId
),
-- Roll up tag statistics per question
tag_rollup as (
  select
    tl.QuestionId,
    count(*) as TagCountForRoll,
    min(tl.FavRankInTag) as BestFavRankInAnyTag,
    avg(tl.AvgScoreByTag) as MeanTagAvgScore,
    max(tl.P90ViewsByTag) as MaxP90ViewsAmongTags
  from tag_level tl
  group by tl.QuestionId
),
-- Final scoring for questions combining multiple signals
question_final as (
  select
    qm.*,
    tr.TagCountForRoll,
    tr.BestFavRankInAnyTag,
    tr.MeanTagAvgScore,
    tr.MaxP90ViewsAmongTags,
    -- Final composite score with null-safe math and caps
    (
      coalesce(qm.QuestionScore,0) * 1.5
      + least(coalesce(qm.ViewCount,0), 200000) * 0.0005
      + coalesce(qm.FavoriteCombined,0) * 0.75
      + coalesce(qm.UpVotes,0) * 0.5
      - coalesce(qm.DownVotes,0) * 0.7
      + coalesce(qm.BountySum,0) * 0.01
      + case when qm.HasStrongAnswer then 5 else 0 end
      + case when qm.IsControversial then 3 else 0 end
      + case when tr.BestFavRankInAnyTag is not null and tr.BestFavRankInAnyTag <= 10 then 2 else 0 end
      + case when tr.MeanTagAvgScore is not null then tr.MeanTagAvgScore * 0.15 else 0 end
    ) as FinalScore
  from question_metrics qm
  left join tag_rollup tr on tr.QuestionId = qm.QuestionId
),
-- Build a contrasting set using set operators: high score or high views, excluding duplicates cluster
highlights as (
  (
    select qf.*
    from question_final qf
    where qf.FinalScore >= (
      select coalesce(avg(FinalScore) + 2 * stddev_pop(FinalScore), 0) from question_final
    )
  )
  union
  (
    select qf.*
    from question_final qf
    where qf.ViewCount >= (
      select coalesce(percentile_cont(0.95) within group (order by ViewCount), 0) from question_final
    )
  )
  except
  (
    select qf.*
    from question_final qf
    join link_agg la on la.QuestionId = qf.QuestionId
    where coalesce(la.DuplicateLinks,0) >= 1
  )
),
-- Rank final results globally and by asker band
ranked as (
  select
    h.*,
    dense_rank() over (order by h.FinalScore desc, h.ViewCount desc nulls last, h.QuestionId) as GlobalRank,
    dense_rank() over (partition by coalesce(h.AskerRepBand,'Newbie') order by h.FinalScore desc) as RankInBand
  from highlights h
)
select
  r.GlobalRank,
  r.RankInBand,
  r.QuestionId,
  r.AskedAt,
  r.AskerId,
  coalesce(r.AskerName, concat('user#', r.AskerId::text)) as AskerName,
  coalesce(r.AskerLocation, 'Unknown') as AskerLocation,
  coalesce(r.AskerRepBand, 'Newbie') as AskerRepBand,
  round(coalesce(r.AskerPerfScore,0)::numeric, 3) as AskerPerfScore,
  r.TagsCsv,
  r.TagDiversity,
  r.QuestionScore,
  r.ViewCount,
  r.FavoriteCombined,
  r.AnswerTotal,
  r.AcceptedCount,
  r.MaxAnswerScore,
  round(coalesce(r.AvgAnswerScore,0)::numeric, 3) as AvgAnswerScore,
  r.UpVotes,
  r.DownVotes,
  r.BountySum,
  r.DuplicateLinks,
  r.RelatedLinks,
  r.CommentCount,
  r.CommentScoreSum,
  r.WasEverClosed,
  r.WasEverReopened,
  r.WasEverProtected,
  round(coalesce(r.SecsPerAnswerUntilFirstLink,0)::numeric, 3) as SecsPerAnswerUntilFirstLink,
  round(coalesce(r.HoursUntilLastComment,0)::numeric, 3) as HoursUntilLastComment,
  r.IsControversial,
  r.HasStrongAnswer,
  r.TagCountForRoll,
  r.BestFavRankInAnyTag,
  round(coalesce(r.MeanTagAvgScore,0)::numeric, 3) as MeanTagAvgScore,
  r.MaxP90ViewsAmongTags,
  round(r.FinalScore::numeric, 3) as FinalScore
from ranked r
where
  -- Complicated predicate mixing null logic and expressions
  (r.FinalScore > 0 and coalesce(r.TagDiversity,0) >= 1)
  and not (r.WasEverClosed and r.WasEverReopened is false and coalesce(r.ViewCount,0) < 500)
  and (
    (r.AskerRepBand in ('Veteran','Legend') and r.AnswerTotal >= 1)
    or (r.AskerRepBand not in ('Veteran','Legend') and coalesce(r.UpVotes,0) - coalesce(r.DownVotes,0) >= 0)
  )
order by r.GlobalRank, r.QuestionId
limit 200;