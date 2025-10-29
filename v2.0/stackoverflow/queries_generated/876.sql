-- {"query": "876.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3146} 
with
params as (
  select
    50::int as top_n_questions,
    interval '365 days' as recent_window,
    10::int as min_answers,
    5::int as min_unique_commenters
),
recent_questions as (
  select
    q.Id as QuestionId,
    q.CreationDate,
    q.Title,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.OwnerUserId,
    coalesce(q.AnswerCount, 0) as AnswerCount,
    count(a.Id) filter (where a.PostTypeId = 2) as ActualAnswerCount,
    max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
    min(a.Score) filter (where a.PostTypeId = 2) as MinAnswerScore
  from Posts q
  left join Posts a
    on a.ParentId = q.Id
   and a.PostTypeId = 2
  where q.PostTypeId = 1
    and q.CreationDate >= (select now() - recent_window from params)
  group by q.Id, q.CreationDate, q.Title, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, q.AnswerCount
),
tag_expanded as (
  select
    rq.*,
    unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2, 0)), '><')) as tag
  from recent_questions rq
),
tag_stats as (
  select
    tag,
    count(distinct QuestionId) as tag_q_count,
    avg(Score::numeric) as tag_avg_q_score,
    percentile_cont(0.9) within group (order by ViewCount) as tag_p90_views
  from tag_expanded
  group by tag
),
question_activity as (
  select
    q.QuestionId,
    count(distinct c.Id) as comment_count,
    count(distinct c.UserId) filter (where c.UserId is not null) as unique_commenters,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites_legacy,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_total
  from recent_questions q
  left join Comments c on c.PostId = q.QuestionId
  left join Votes v on v.PostId = q.QuestionId
  group by q.QuestionId
),
owner_metrics as (
  select
    u.Id as OwnerUserId,
    u.Reputation,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    date_part('day', now() - u.CreationDate) as AccountAgeDays,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(distinct case when b.TagBased = 1 then b.Name end) as DistinctTagBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
),
dup_clusters as (
  select
    pl.RelatedPostId as CanonicalId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
    min(pl.CreationDate) as FirstLinkDate,
    max(pl.CreationDate) as LastLinkDate
  from PostLinks pl
  group by pl.RelatedPostId
),
edit_events as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesInHistory,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents
  from PostHistory ph
  group by ph.PostId
),
question_quality as (
  select
    rq.QuestionId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.ActualAnswerCount,
    rq.MaxAnswerScore,
    rq.MinAnswerScore,
    qa.comment_count,
    qa.unique_commenters,
    qa.upvotes,
    qa.downvotes,
    qa.favorites_legacy,
    qa.bounty_total,
    em.Reputation as OwnerReputation,
    em.AccountAgeDays,
    em.GoldBadges,
    em.SilverBadges,
    em.BronzeBadges,
    em.DistinctTagBadges,
    coalesce(ec.EditCount,0) as EditCount,
    ec.LastEditDate,
    coalesce(ec.CloseVotesInHistory,0) as CloseVotesInHistory,
    coalesce(ec.ReopenEvents,0) as ReopenEvents,
    coalesce(dc.DuplicateCount,0) as DuplicateCount,
    coalesce(dc.LinkedCount,0) as LinkedCount,
    dc.FirstLinkDate,
    dc.LastLinkDate
  from recent_questions rq
  left join question_activity qa on qa.QuestionId = rq.QuestionId
  left join owner_metrics em on em.OwnerUserId = rq.OwnerUserId
  left join edit_events ec on ec.PostId = rq.QuestionId
  left join dup_clusters dc on dc.CanonicalId = rq.QuestionId
),
scored as (
  select
    qq.*,
    -- handle potential nulls and edge cases with defensive math
    case
      when qq.ViewCount is null or qq.ViewCount = 0 then 0
      else least(1.0, log(greatest(qq.ViewCount,1)) / 12.0)
    end as norm_views,
    case
      when qq.Score is null then 0
      else greatest(-1.0, least(1.0, qq.Score / 50.0::numeric))
    end as norm_score,
    coalesce(qq.ActualAnswerCount,0) as answers,
    case when coalesce(qq.ActualAnswerCount,0) = 0 then 0 else least(1.0, qq.ActualAnswerCount / 10.0::numeric) end as norm_answers,
    case when coalesce(qq.unique_commenters,0) = 0 then 0 else least(1.0, qq.unique_commenters / 10.0::numeric) end as norm_commenters,
    coalesce(qq.bounty_total,0) / 100.0::numeric as norm_bounty,
    case when qq.OwnerReputation is null then 0 else least(1.0, log(greatest(qq.OwnerReputation,1)) / 10.0) end as norm_owner_rep,
    case when qq.EditCount is null then 0 else least(1.0, qq.EditCount / 8.0::numeric) end as norm_edits,
    case when qq.DuplicateCount > 0 then -0.5 else 0 end as dup_penalty,
    case when qq.CloseVotesInHistory > 0 then -0.3 else 0 end as close_penalty
  from question_quality qq
),
ranked as (
  select
    s.*,
    (
      0.25*norm_views +
      0.25*norm_score +
      0.15*norm_answers +
      0.10*norm_commenters +
      0.10*norm_owner_rep +
      0.05*norm_edits +
      0.07*norm_bounty +
      dup_penalty + close_penalty
    ) as quality_score,
    row_number() over (
      order by
        (
          0.25*norm_views +
          0.25*norm_score +
          0.15*norm_answers +
          0.10*norm_commenters +
          0.10*norm_owner_rep +
          0.05*norm_edits +
          0.07*norm_bounty +
          dup_penalty + close_penalty
        ) desc,
        coalesce(LastEditDate, CreationDate) desc,
        QuestionId
    ) as rn
  from scored s
  where s.answers >= (select min_answers from params)
    and coalesce(s.unique_commenters,0) >= (select min_unique_commenters from params)
),
top_questions as (
  select *
  from ranked
  where rn <= (select top_n_questions from params)
),
-- derive tag-level aggregation just for those top questions
top_tag_expanded as (
  select
    tq.QuestionId,
    unnest(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2, 0)), '><')) as tag
  from top_questions tq
  join Posts p on p.Id = tq.QuestionId
),
top_tag_stats as (
  select
    tag,
    count(distinct QuestionId) as top_tag_q_count
  from top_tag_expanded
  group by tag
),
-- build a correlated subquery measure: recent answer velocity per question
answer_velocity as (
  select
    q.Id as QuestionId,
    count(a.Id) filter (where a.CreationDate >= now() - interval '30 days') as answers_30d,
    count(a.Id) filter (where a.CreationDate >= now() - interval '7 days') as answers_7d
  from Posts q
  left join Posts a
    on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
    and q.Id in (select QuestionId from top_questions)
  group by q.Id
),
-- generate an outer-joined view of accepted vs max-scored answer using self-join
answers_comp as (
  select
    q.Id as QuestionId,
    acc.Id as AcceptedId,
    acc.Score as AcceptedScore,
    ms.Id as MaxScoreAnswerId,
    ms.Score as MaxScoreAnswerScore
  from Posts q
  left join Posts acc
    on acc.Id = q.AcceptedAnswerId
  left join lateral (
    select a.Id, a.Score
    from Posts a
    where a.ParentId = q.Id and a.PostTypeId = 2
    order by a.Score desc nulls last, a.Id
    limit 1
  ) ms on true
  where q.Id in (select QuestionId from top_questions)
),
-- final assembly with set operators to add "bonus" rows for tags having strong global metrics
bonus_tags as (
  select
    tts.tag,
    tts.top_tag_q_count,
    ts.tag_q_count,
    ts.tag_avg_q_score,
    ts.tag_p90_views
  from top_tag_stats tts
  left join tag_stats ts using (tag)
)
select
  tq.QuestionId,
  tq.Title,
  tq.quality_score,
  tq.Score as QuestionScore,
  tq.ViewCount,
  tq.answers as AnswerCount,
  tq.unique_commenters as UniqueCommenters,
  tq.bounty_total as BountyTotal,
  tq.OwnerReputation,
  tq.AccountAgeDays,
  tq.EditCount,
  tq.DuplicateCount,
  tq.CloseVotesInHistory,
  av.answers_30d,
  av.answers_7d,
  ac.AcceptedId,
  ac.AcceptedScore,
  ac.MaxScoreAnswerId,
  ac.MaxScoreAnswerScore,
  (
    select string_agg(tag || ':' || top_tag_q_count::text, ', ' order by tag)
    from top_tag_expanded tte
    join top_tag_stats tts on tts.tag = tte.tag
    where tte.QuestionId = tq.QuestionId
  ) as TopTagsSummary,
  (
    select string_agg(distinct coalesce(c.UserDisplayName, 'uid:'||c.UserId::text), ', ' order by 1)
    from Comments c
    where c.PostId = tq.QuestionId
      and (c.Score is null or c.Score >= 0)
      and c.Text is not null
      and length(trim(c.Text)) > 0
  ) as NonNegativeCommenters,
  case
    when tq.LastEditDate is null then 'never edited'
    when tq.LastEditDate >= now() - interval '7 days' then 'edited this week'
    when tq.LastEditDate >= now() - interval '30 days' then 'edited this month'
    else 'edited earlier'
  end as EditRecencyBand
from top_questions tq
left join answer_velocity av on av.QuestionId = tq.QuestionId
left join answers_comp ac on ac.QuestionId = tq.QuestionId
where not exists (
  select 1
  from PostHistory ph
  where ph.PostId = tq.QuestionId
    and ph.PostHistoryTypeId in (12) -- deleted
)
union all
select
  null::int as QuestionId,
  ('[TAG BONUS] ' || bt.tag)::varchar(300) as Title,
  null::numeric as quality_score,
  null::int as QuestionScore,
  bt.tag_p90_views::int as ViewCount,
  bt.top_tag_q_count as AnswerCount,
  null::int as UniqueCommenters,
  null::int as BountyTotal,
  null::int as OwnerReputation,
  null::numeric as AccountAgeDays,
  null::int as EditCount,
  null::int as DuplicateCount,
  null::int as CloseVotesInHistory,
  null::int as answers_30d,
  null::int as answers_7d,
  null::int as AcceptedId,
  null::int as AcceptedScore,
  null::int as MaxScoreAnswerId,
  null::int as MaxScoreAnswerScore,
  null::text as TopTagsSummary,
  null::text as NonNegativeCommenters,
  'tag-bonus' as EditRecencyBand
from bonus_tags bt
where bt.tag_p90_views is not null
  and bt.tag_q_count >= 25
order by
  quality_score desc nulls last,
  ViewCount desc nulls last,
  Title asc
limit (select top_n_questions + 20 from params);