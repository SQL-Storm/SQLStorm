-- {"query": "663.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2875} 
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, '(anonymous)') as owner_name,
    u.reputation,
    u.location,
    case when p.posttypeid = 1 then 1 else 0 end as is_question
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
  select
    rp.*,
    unnest(string_to_array(substring(rp.tags, 2, length(rp.tags) - 2), '><')) as tag
  from recent_posts rp
  where rp.is_question = 1
),
tag_stats as (
  select
    te.tag,
    count(*) as q_count,
    sum(te.viewcount) as total_views,
    avg(te.score) as avg_q_score,
    percentile_cont(0.5) within group (order by te.score) as med_q_score
  from tag_expanded te
  group by te.tag
  having count(*) >= 5
),
answers as (
  select
    a.id,
    a.parentid as question_id,
    a.creationdate,
    a.owneruserid,
    a.score,
    coalesce(a.commentcount, 0) as commentcount
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
answerer_activity as (
  select
    an.owneruserid as user_id,
    count(*) as ans_count,
    sum(case when an.score > 0 then 1 else 0 end) as pos_ans,
    sum(case when an.score < 0 then 1 else 0 end) as neg_ans,
    avg(an.score) as avg_ans_score,
    sum(an.commentcount) as total_ans_comments,
    min(an.creationdate) as first_ans_date,
    max(an.creationdate) as last_ans_date
  from answers an
  where an.owneruserid is not null
  group by an.owneruserid
),
question_metrics as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.score as q_score,
    q.viewcount as q_views,
    q.creationdate as q_date,
    count(a.id) as ans_count,
    max(a.score) as best_ans_score,
    sum(case when a.score > 0 then 1 else 0 end) as pos_ans_count,
    sum(case when a.score < 0 then 1 else 0 end) as neg_ans_count,
    avg(a.score) as avg_ans_score,
    count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers
  from recent_posts q
  left join answers a on a.question_id = q.id
  where q.is_question = 1
  group by q.id, q.owneruserid, q.score, q.viewcount, q.creationdate
),
votes_last_year as (
  select
    v.postid,
    v.votetypeid,
    count(*) as vcnt
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by v.postid, v.votetypeid
),
vote_pivot as (
  select
    q.id as postid,
    coalesce(max(case when v.votetypeid = 2 then v.vcnt end), 0) as upvotes,
    coalesce(max(case when v.votetypeid = 3 then v.vcnt end), 0) as downvotes,
    coalesce(max(case when v.votetypeid = 5 then v.vcnt end), 0) as favorites
  from recent_posts q
  left join votes_last_year v on v.postid = q.id
  group by q.id
),
close_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_date,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
  from posthistory ph
  where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
  group by ph.postid
),
dup_links as (
  select
    pl.postid as dup_of,
    count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
  group by pl.postid
),
badge_summary as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as golds,
    sum(case when b.class = 2 then 1 else 0 end) as silvers,
    sum(case when b.class = 3 then 1 else 0 end) as bronzes,
    sum(case when b.tagbased then 1 else 0 end) as tag_badges
  from badges b
  where b.date >= (select max(date) - interval '365 days' from badges)
  group by b.userid
),
user_rollup as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.upvotes,
    u.downvotes,
    u.views,
    extract(epoch from (now() - u.creationdate)) / 86400.0 as account_age_days
  from users u
),
question_tag_enriched as (
  select
    qm.*,
    te.tag,
    ts.q_count as tag_q_count,
    ts.total_views as tag_total_views,
    ts.avg_q_score as tag_avg_q_score,
    ts.med_q_score as tag_med_q_score
  from question_metrics qm
  left join tag_expanded te on te.id = qm.question_id
  left join tag_stats ts on ts.tag = te.tag
),
quality_scored as (
  select
    qte.question_id,
    qte.asker_id,
    qte.q_score,
    qte.q_views,
    qte.q_date,
    qte.ans_count,
    qte.best_ans_score,
    qte.pos_ans_count,
    qte.neg_ans_count,
    qte.avg_ans_score,
    qte.distinct_answerers,
    qte.tag,
    qte.tag_q_count,
    qte.tag_total_views,
    qte.tag_avg_q_score,
    qte.tag_med_q_score,
    vp.upvotes,
    vp.downvotes,
    vp.favorites,
    coalesce(ce.close_votes, 0) as close_votes,
    coalesce(ce.reopen_votes, 0) as reopen_votes,
    ce.last_close_date,
    ce.last_reopen_date,
    ce.last_close_reason_raw,
    coalesce(dl.duplicate_marks, 0) as duplicate_marks,
    coalesce(dl.related_links, 0) as related_links,
    -- composite quality score with NULL-safe math and clipping
    greatest(0.0, least(100.0,
      coalesce(qte.q_score, 0) * 2.0
      + coalesce(vp.upvotes, 0) * 1.0
      - coalesce(vp.downvotes, 0) * 1.5
      + coalesce(qte.best_ans_score, 0) * 1.25
      + coalesce(qte.ans_count, 0) * 0.75
      + coalesce(qte.distinct_answerers, 0) * 0.5
      + ln(1 + coalesce(qte.q_views, 0)) * 1.2
      - coalesce(ce.close_votes, 0) * 5.0
      - coalesce(dl.duplicate_marks, 0) * 8.0
      + coalesce(vp.favorites, 0) * 0.9
    )) as quality_score
  from question_tag_enriched qte
  left join vote_pivot vp on vp.postid = qte.question_id
  left join close_events ce on ce.postid = qte.question_id
  left join dup_links dl on dl.dup_of = qte.question_id
),
ranked_per_tag as (
  select
    qs.*,
    row_number() over (partition by qs.tag order by qs.quality_score desc, qs.q_date desc) as rn_tag,
    rank() over (partition by qs.tag order by qs.quality_score desc) as rnk_tag,
    percentile_disc(0.9) within group (order by qs.quality_score) over (partition by qs.tag) as p90_tag_score
  from quality_scored qs
),
asker_enriched as (
  select
    rpt.*,
    ur.displayname as asker_name,
    ur.reputation as asker_rep,
    ur.upvotes as asker_upvotes,
    ur.downvotes as asker_downvotes,
    ur.views as asker_profile_views,
    ur.account_age_days as asker_account_age_days,
    bs.golds as asker_golds,
    bs.silvers as asker_silvers,
    bs.bronzes as asker_bronzes,
    bs.tag_badges as asker_tag_badges
  from ranked_per_tag rpt
  left join user_rollup ur on ur.user_id = rpt.asker_id
  left join badge_summary bs on bs.userid = rpt.asker_id
),
answerer_mix as (
  select
    a.question_id,
    json_agg(
      json_build_object(
        'user_id', aa.user_id,
        'ans_count', aa.ans_count,
        'avg_ans_score', round(coalesce(aa.avg_ans_score, 0)::numeric, 2),
        'pos_ratio', case when aa.ans_count > 0 then round(aa.pos_ans::numeric / aa.ans_count, 3) else 0 end
      )
      order by aa.avg_ans_score desc
    ) filter (where aa.user_id is not null) as top_answerers
  from answers a
  join answerer_activity aa on aa.user_id = a.owneruserid
  group by a.question_id
),
final_rank as (
  select
    ae.*,
    am.top_answerers,
    dense_rank() over (order by ae.quality_score desc, ae.q_date desc) as global_rank,
    case
      when ae.quality_score >= ae.p90_tag_score then 'TOP_DECILE'
      when ae.rnk_tag <= 5 then 'TOP5_TAG'
      else 'OTHER'
    end as tag_bucket
  from asker_enriched ae
  left join answerer_mix am on am.question_id = ae.question_id
),
closed_reason_enriched as (
  select
    fr.*,
    case
      when fr.last_close_reason_raw ~ '^[0-9]+$' then
        (select crt.name from closereasontypes crt where crt.id = fr.last_close_reason_raw::int)
      else null
    end as last_close_reason_name
  from final_rank fr
)
select
  cre.tag,
  cre.question_id,
  cre.asker_id,
  coalesce(cre.asker_name, '(unknown)') as asker_name,
  coalesce(cre.asker_rep, 0) as asker_rep,
  cre.q_score,
  cre.q_views,
  cre.ans_count,
  cre.best_ans_score,
  cre.avg_ans_score,
  cre.upvotes,
  cre.downvotes,
  cre.favorites,
  cre.close_votes,
  cre.reopen_votes,
  coalesce(cre.last_close_reason_name, '(n/a)') as last_close_reason,
  cre.duplicate_marks,
  cre.related_links,
  round(cre.quality_score::numeric, 2) as quality_score,
  cre.rn_tag as rownum_in_tag,
  cre.rnk_tag as rank_in_tag,
  cre.p90_tag_score,
  cre.global_rank,
  cre.tag_bucket,
  cre.top_answerers
from closed_reason_enriched cre
where
  -- variety of complex predicates for benchmarking
  (cre.ans_count >= 1 or cre.duplicate_marks = 0)
  and not (cre.upvotes is null and cre.downvotes is null)
  and coalesce(cre.asker_rep, 0) >= 1
  and (
    cre.tag_bucket in ('TOP_DECILE', 'TOP5_TAG')
    or (cre.quality_score >= 50 and coalesce(cre.close_votes, 0) = 0)
  )
  and (
    cre.tag is not null
    and length(cre.tag) between 2 and 35
    and lower(cre.tag) not like any (array['%test%', '%debug%', '%dummy%'])
  )
order by
  cre.quality_score desc,
  cre.p90_tag_score desc,
  cre.q_date desc
limit 250;