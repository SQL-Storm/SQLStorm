-- {"query": "113.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3432} 
with
params as (
  select
    cast(100 as int) as top_n_questions,
    cast(365 as int) as recent_days,
    cast(0.05 as numeric) as rare_tag_threshold_ratio
),
recent_activity as (
  select
    p.Id as PostId,
    coalesce(p.LastActivityDate, p.CreationDate) as ActivityDate,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    p.Title,
    date_trunc('day', coalesce(p.LastActivityDate, p.CreationDate)) as ActivityDay
  from Posts p
  join params prm on true
  where coalesce(p.LastActivityDate, p.CreationDate) >= now() - (prm.recent_days || ' days')::interval
    and p.PostTypeId in (1,2)
),
question_base as (
  select
    q.PostId,
    q.ActivityDate,
    q.OwnerUserId,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.Title,
    q.Tags
  from recent_activity q
  where q.PostTypeId = 1
),
answer_base as (
  select
    a.PostId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    a.ActivityDate,
    a.ActivityDay,
    p.ParentId as QuestionId
  from recent_activity a
  join Posts p on p.Id = a.PostId and a.PostTypeId = 2 and p.PostTypeId = 2
),
answers_agg as (
  select
    ab.QuestionId,
    count(*) as answer_cnt_recent,
    sum(case when ab.Score > 0 then 1 else 0 end) as pos_answers,
    sum(case when ab.Score < 0 then 1 else 0 end) as neg_answers,
    max(ab.Score) as max_answer_score,
    min(ab.Score) as min_answer_score,
    avg(ab.Score::numeric) as avg_answer_score,
    count(distinct ab.OwnerUserId) filter (where ab.OwnerUserId is not null) as distinct_answerers
  from answer_base ab
  group by ab.QuestionId
),
votes_recent as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes_recent,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes_recent,
    sum(case when v.VoteTypeId = 10 then 1 else 0 end) as deletions_recent
  from Votes v
  join params prm on true
  where v.CreationDate >= now() - (prm.recent_days || ' days')::interval
  group by v.PostId
),
favorites_recent as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 5) as favorites_recent
  from Votes v
  join params prm on true
  where v.CreationDate >= now() - (prm.recent_days || ' days')::interval
  group by v.PostId
),
comments_recent as (
  select
    c.PostId,
    count(*) as comments_recent,
    max(c.Score) as max_comment_score_recent,
    avg(c.Score::numeric) as avg_comment_score_recent,
    count(distinct c.UserId) filter (where c.UserId is not null) as distinct_commenters_recent
  from Comments c
  join params prm on true
  where c.CreationDate >= now() - (prm.recent_days || ' days')::interval
  group by c.PostId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    date_trunc('day', u.CreationDate) as UserCreatedDay,
    coalesce(nullif(trim(u.Location), ''), '(unknown)') as NormLocation
  from Users u
),
badge_counts as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.Class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.Class = 3 then 1 else 0 end) as bronze_count,
    sum(case when b.TagBased = 1 then 1 else 0 end) as tag_based_count
  from Badges b
  group by b.UserId
),
-- explode tags for questions
question_tags as (
  select
    qb.PostId,
    lower(trim(tg)) as TagName
  from question_base qb
  cross join lateral unnest(string_to_array(substring(qb.Tags, 2, length(qb.Tags)-2), '><')) as tg
),
tag_rarity as (
  select
    qt.TagName,
    count(distinct qt.PostId) as question_count_recent
  from question_tags qt
  group by qt.TagName
),
rare_tag_threshold as (
  select
    percentile_disc(prm.rare_tag_threshold_ratio) within group (order by tr.question_count_recent) as cutoff
  from tag_rarity tr
  cross join params prm
),
question_tag_features as (
  select
    qt.PostId,
    count(*) as tag_count,
    count(*) filter (where tr.question_count_recent <= rtt.cutoff) as rare_tag_count,
    min(tr.question_count_recent) as min_tag_popularity,
    max(tr.question_count_recent) as max_tag_popularity
  from question_tags qt
  join tag_rarity tr on tr.TagName = qt.TagName
  cross join rare_tag_threshold rtt
  group by qt.PostId
),
edits_recent as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as edit_events,
    count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35)) as moderation_events,
    max(ph.CreationDate) as last_edit_date
  from PostHistory ph
  join params prm on true
  where ph.CreationDate >= now() - (prm.recent_days || ' days')::interval
  group by ph.PostId
),
closures_recent as (
  select
    ph.PostId,
    min(ph.CreationDate) as first_close_date,
    max(ph.CreationDate) as last_close_date,
    count(*) as close_events,
    mode() within group (order by try_cast(ph.Comment as int)) as most_common_close_reason_id
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
    and ph.CreationDate >= now() - interval '3 years'
  group by ph.PostId
),
duplicate_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as dup_links_out,
    count(*) filter (where pl.LinkTypeId = 3 and pl.PostId <> pl.RelatedPostId) as dup_links_out_distinct,
    count(*) filter (where pl.LinkTypeId = 1) as linked_out
  from PostLinks pl
  group by pl.PostId
),
inbound_duplicate_links as (
  select
    pl.RelatedPostId as PostId,
    count(*) filter (where pl.LinkTypeId = 3) as dup_links_in
  from PostLinks pl
  group by pl.RelatedPostId
),
engagement_score as (
  select
    qb.PostId,
    qb.Title,
    qb.Tags,
    qb.Score as q_score,
    qb.ViewCount,
    qb.AnswerCount,
    qb.FavoriteCount,
    coalesce(vr.upvotes_recent,0) as upvotes_recent,
    coalesce(vr.downvotes_recent,0) as downvotes_recent,
    coalesce(fr.favorites_recent,0) as favorites_recent,
    coalesce(cr.comments_recent,0) as comments_recent,
    coalesce(cr.max_comment_score_recent,0) as max_comment_score_recent,
    coalesce(cr.avg_comment_score_recent,0) as avg_comment_score_recent,
    coalesce(aa.answer_cnt_recent,0) as answer_cnt_recent,
    coalesce(aa.pos_answers,0) as pos_answers,
    coalesce(aa.neg_answers,0) as neg_answers,
    coalesce(aa.max_answer_score,0) as max_answer_score,
    coalesce(aa.min_answer_score,0) as min_answer_score,
    coalesce(aa.avg_answer_score,0) as avg_answer_score,
    coalesce(aa.distinct_answerers,0) as distinct_answerers,
    coalesce(qtf.tag_count,0) as tag_count,
    coalesce(qtf.rare_tag_count,0) as rare_tag_count,
    coalesce(qtf.min_tag_popularity,0) as min_tag_popularity,
    coalesce(qtf.max_tag_popularity,0) as max_tag_popularity,
    coalesce(er.edit_events,0) as edit_events,
    coalesce(er.moderation_events,0) as moderation_events,
    er.last_edit_date,
    coalesce(cl.close_events,0) as close_events,
    cl.first_close_date,
    cl.last_close_date,
    coalesce(dl.dup_links_out,0) as dup_links_out,
    coalesce(dl.dup_links_out_distinct,0) as dup_links_out_distinct,
    coalesce(dl.linked_out,0) as linked_out,
    coalesce(idl.dup_links_in,0) as dup_links_in,
    coalesce(vr.deletions_recent,0) as deletions_recent
  from question_base qb
  left join votes_recent vr on vr.PostId = qb.PostId
  left join favorites_recent fr on fr.PostId = qb.PostId
  left join comments_recent cr on cr.PostId = qb.PostId
  left join answers_agg aa on aa.QuestionId = qb.PostId
  left join question_tag_features qtf on qtf.PostId = qb.PostId
  left join edits_recent er on er.PostId = qb.PostId
  left join closures_recent cl on cl.PostId = qb.PostId
  left join duplicate_links dl on dl.PostId = qb.PostId
  left join inbound_duplicate_links idl on idl.PostId = qb.PostId
),
owner_enriched as (
  select
    e.*,
    u.UserId as OwnerUserId,
    us.Reputation,
    us.UpVotes,
    us.DownVotes,
    us.Views as UserProfileViews,
    us.NormLocation,
    coalesce(bc.gold_count,0) as gold_badges,
    coalesce(bc.silver_count,0) as silver_badges,
    coalesce(bc.bronze_count,0) as bronze_badges,
    coalesce(bc.tag_based_count,0) as tag_based_badges
  from engagement_score e
  left join Posts p on p.Id = e.PostId
  left join user_stats us on us.UserId = p.OwnerUserId
  left join badge_counts bc on bc.UserId = p.OwnerUserId
  left join lateral (select p.OwnerUserId) u on true
),
scored as (
  select
    oe.*,
    (
      coalesce(oe.q_score,0) * 2
      + log(1 + greatest(oe.ViewCount,0)) * 3
      + coalesce(oe.answer_cnt_recent,0) * 4
      + coalesce(oe.distinct_answerers,0) * 2
      + coalesce(oe.upvotes_recent,0) * 3
      - coalesce(oe.downvotes_recent,0) * 2
      + coalesce(oe.favorites_recent,0) * 5
      + coalesce(oe.comments_recent,0) * 1
      - coalesce(oe.close_events,0) * 10
      - case when oe.deletions_recent > 0 then 50 else 0 end
      - case when oe.rare_tag_count >= 2 then 1 else 0 end
      + least(coalesce(oe.max_answer_score,0), 50)
      + (case when oe.edit_events > 0 then 2 else 0 end)
      + (case when oe.moderation_events > 0 then -3 else 0 end)
      + (case when oe.dup_links_in > 0 then -5 else 0 end)
    )::numeric as engagement_score
  from owner_enriched oe
),
ranked as (
  select
    s.*,
    row_number() over (order by s.engagement_score desc nulls last, s.ViewCount desc, s.q_score desc, s.PostId) as rn,
    rank() over (order by s.engagement_score desc nulls last) as rnk,
    dense_rank() over (order by s.engagement_score desc nulls last) as drnk,
    percentile_cont(0.5) within group (order by s.engagement_score) over () as median_score,
    avg(s.engagement_score) over () as avg_score_all,
    stddev_pop(s.engagement_score) over () as stddev_score_all
  from scored s
),
location_rollup as (
  select
    NormLocation,
    count(*) as q_count,
    avg(engagement_score) as avg_engagement_by_loc
  from ranked
  group by NormLocation
),
final as (
  select
    r.PostId,
    coalesce(r.Title, '(no title)') as Title,
    coalesce(r.Tags, '[]') as TagsRaw,
    r.engagement_score,
    r.ViewCount,
    r.q_score,
    r.AnswerCount,
    r.answer_cnt_recent,
    r.pos_answers,
    r.neg_answers,
    r.max_answer_score,
    r.min_answer_score,
    r.avg_answer_score,
    r.distinct_answerers,
    r.upvotes_recent,
    r.downvotes_recent,
    r.favorites_recent,
    r.comments_recent,
    r.tag_count,
    r.rare_tag_count,
    r.min_tag_popularity,
    r.max_tag_popularity,
    r.edit_events,
    r.moderation_events,
    r.close_events,
    r.dup_links_out,
    r.dup_links_out_distinct,
    r.dup_links_in,
    r.linked_out,
    r.Reputation as OwnerReputation,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.tag_based_badges,
    r.NormLocation,
    lr.avg_engagement_by_loc,
    r.rn,
    r.rnk,
    r.drnk,
    r.median_score,
    r.avg_score_all,
    r.stddev_score_all,
    case
      when r.engagement_score is null then 'unknown'
      when r.engagement_score >= coalesce(r.avg_score_all + 2*nullif(r.stddev_score_all,0), r.engagement_score + 1) then 'outlier-high'
      when r.engagement_score <= coalesce(r.avg_score_all - 2*nullif(r.stddev_score_all,0), r.engagement_score - 1) then 'outlier-low'
      else 'normal'
    end as score_band,
    -- string expression combining useful bits
    ('Q' || r.PostId::text) || ' | ' ||
      left(coalesce(r.Title,''), 80) || ' | ' ||
      coalesce(r.Tags,'') || ' | ' ||
      coalesce(r.NormLocation,'') as summary_line
  from ranked r
  left join location_rollup lr on lr.NormLocation = r.NormLocation
)
select *
from final f
join params prm on true
where f.rn <= prm.top_n_questions
order by f.engagement_score desc nulls last, f.ViewCount desc, f.q_score desc, f.PostId;