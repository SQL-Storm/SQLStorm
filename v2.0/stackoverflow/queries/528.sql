-- {"query": "528.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3431}
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         regexp_replace(coalesce(u.websiteurl, ''), '^https?://(www\.)?', '', 'i') as site_host
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
q_posts as (
  select p.id as post_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.favoritecount
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.id as post_id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
post_votes as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
         max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
q_activity as (
  select q.post_id,
         q.user_id,
         q.creationdate as question_created_at,
         q.score as question_score,
         q.viewcount,
         q.title,
         q.tags,
         q.acceptedanswerid,
         q.favoritecount,
         pv.net_votes as q_net_votes,
         pv.upvotes as q_upvotes,
         pv.downvotes as q_downvotes,
         pv.last_vote_at as q_last_vote_at
  from q_posts q
  left join post_votes pv on pv.postid = q.post_id
),
a_activity as (
  select a.post_id,
         a.question_id,
         a.user_id,
         a.creationdate as answer_created_at,
         a.score as answer_score,
         pv.net_votes as a_net_votes,
         pv.upvotes as a_upvotes,
         pv.downvotes as a_downvotes,
         pv.last_vote_at as a_last_vote_at
  from a_posts a
  left join post_votes pv on pv.postid = a.post_id
),
first_answers as (
  select aa.question_id,
         aa.post_id as first_answer_id,
         aa.user_id as first_answerer_id,
         aa.answer_created_at as first_answer_at,
         aa.answer_score as first_answer_score,
         row_number() over (partition by aa.question_id order by aa.answer_created_at asc, aa.post_id asc) as rn
  from a_activity aa
),
accepted_answers as (
  select qa.post_id as question_id,
         qa.acceptedanswerid as accepted_answer_id
  from q_activity qa
  where qa.acceptedanswerid is not null
),
question_metrics as (
  select
    qa.post_id as question_id,
    qa.user_id as asker_id,
    qa.question_created_at,
    qa.title,
    qa.tags,
    qa.viewcount,
    qa.question_score,
    qa.q_net_votes,
    qa.q_upvotes,
    qa.q_downvotes,
    qa.q_last_vote_at,
    coalesce(fa.first_answer_id, -1) as first_answer_id,
    fa.first_answerer_id,
    fa.first_answer_at,
    fa.first_answer_score,
    aa.accepted_answer_id,
    case when aa.accepted_answer_id = fa.first_answer_id then 1 else 0 end as first_is_accepted,
    cast(extract(epoch from (fa.first_answer_at - qa.question_created_at)) as bigint) as secs_to_first_answer,
    count(ap.post_id) as total_answers,
    max(ap.answer_created_at) as last_answer_at,
    sum(ap.a_net_votes) as sum_answer_net_votes,
    avg(ap.a_net_votes) as avg_answer_net_votes
  from q_activity qa
  left join first_answers fa on fa.question_id = qa.post_id and fa.rn = 1
  left join accepted_answers aa on aa.question_id = qa.post_id
  left join a_activity ap on ap.question_id = qa.post_id
  group by qa.post_id, qa.user_id, qa.question_created_at, qa.title, qa.tags, qa.viewcount, qa.question_score, qa.q_net_votes, qa.q_upvotes, qa.q_downvotes, qa.q_last_vote_at, fa.first_answer_id, fa.first_answerer_id, fa.first_answer_at, fa.first_answer_score, aa.accepted_answer_id
),
tag_expanded as (
  select qm.question_id,
         unnest(string_to_array(substring(qm.tags, 2, length(qm.tags)-2), '><')) as tag
  from question_metrics qm
  where qm.tags is not null and length(qm.tags) > 2
),
interesting_tags as (
  select te.tag,
         count(*) as tag_q_count,
         sum(case when qm.viewcount >= 1000 then 1 else 0 end) as popular_qs
  from tag_expanded te
  join question_metrics qm on qm.question_id = te.question_id
  group by te.tag
  having count(*) >= 10
),
user_badges as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold,
         sum(case when b.class = 2 then 1 else 0 end) as silver,
         sum(case when b.class = 3 then 1 else 0 end) as bronze,
         sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
user_activity as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(ub.gold,0) as gold,
         coalesce(ub.silver,0) as silver,
         coalesce(ub.bronze,0) as bronze,
         coalesce(ub.tag_badges,0) as tag_badges,
         sum(case when p.posttypeid = 1 then 1 else 0 end) as question_count,
         sum(case when p.posttypeid = 2 then 1 else 0 end) as answer_count,
         sum(coalesce(p.score,0)) as total_post_score,
         max(p.lastactivitydate) as last_activity_at
  from users u
  left join user_badges ub on ub.userid = u.id
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, ub.gold, ub.silver, ub.bronze, ub.tag_badges
),
dupe_links as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
         count(*) filter (where pl.linktypeid = 1) as linked_marks
  from postlinks pl
  group by pl.postid
),
close_events as (
  select ph.postid as question_id,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen_at,
         count(*) filter (
           where ph.posthistorytypeid = 10
             and (ph.comment ~ '(^|[^0-9])101([^0-9]|$)' or ph.comment = '101')
         ) as duplicate_close_reasons
  from posthistory ph
  group by ph.postid
),
comment_stats as (
  select c.postid as post_id,
         count(*) as comment_count,
         avg(c.score) as avg_comment_score,
         max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
ranked_questions as (
  select
    qm.question_id,
    qm.asker_id,
    qm.question_created_at,
    qm.title,
    qm.tags,
    qm.viewcount,
    qm.question_score,
    qm.q_net_votes,
    qm.q_upvotes,
    qm.q_downvotes,
    qm.q_last_vote_at,
    qm.first_answer_id,
    qm.first_answerer_id,
    qm.first_answer_at,
    qm.first_answer_score,
    qm.accepted_answer_id,
    qm.first_is_accepted,
    qm.secs_to_first_answer,
    qm.total_answers,
    qm.last_answer_at,
    qm.sum_answer_net_votes,
    qm.avg_answer_net_votes,
    coalesce(cs.comment_count,0) as comment_count,
    coalesce(cs.avg_comment_score,0) as avg_comment_score,
    cs.last_comment_at,
    coalesce(dl.duplicate_marks,0) as duplicate_marks,
    coalesce(dl.linked_marks,0) as linked_marks,
    coalesce(ce.close_votes,0) as close_votes,
    coalesce(ce.reopen_votes,0) as reopen_votes,
    ce.last_close_or_reopen_at,
    coalesce(ce.duplicate_close_reasons,0) as duplicate_close_reasons,
    (
      greatest(qm.viewcount,0) * 0.001
      + coalesce(qm.q_net_votes,0) * 2
      + coalesce(qm.total_answers,0) * 1.5
      + case when qm.first_is_accepted = 1 then 5 else 0 end
      - coalesce(ce.close_votes,0) * 3
      - coalesce(dl.duplicate_marks,0) * 2
      + least(coalesce(qm.first_answer_score,0), 50) * 0.5
      + case when (timestamp '2024-10-01 12:34:56' - qm.question_created_at) <= interval '30 days' then 10 else 0 end
    ) as hotness_score
  from question_metrics qm
  left join comment_stats cs on cs.post_id = qm.question_id
  left join dupe_links dl on dl.question_id = qm.question_id
  left join close_events ce on ce.question_id = qm.question_id
  group by qm.question_id, qm.asker_id, qm.question_created_at, qm.title, qm.tags, qm.viewcount, qm.question_score, qm.q_net_votes, qm.q_upvotes, qm.q_downvotes, qm.q_last_vote_at, qm.first_answer_id, qm.first_answerer_id, qm.first_answer_at, qm.first_answer_score, qm.accepted_answer_id, qm.first_is_accepted, qm.secs_to_first_answer, qm.total_answers, qm.last_answer_at, qm.sum_answer_net_votes, qm.avg_answer_net_votes, cs.comment_count, cs.avg_comment_score, cs.last_comment_at, dl.duplicate_marks, dl.linked_marks, ce.close_votes, ce.reopen_votes, ce.last_close_or_reopen_at, ce.duplicate_close_reasons
),
user_enriched as (
  select
    ua.*,
    case
      when ua.reputation >= 100000 then 'legend'
      when ua.reputation >= 20000 then 'expert'
      when ua.reputation >= 3000 then 'pro'
      when ua.reputation >= 500 then 'regular'
      else 'newbie'
    end as rep_band
  from user_activity ua
),
question_owner as (
  select rq.question_id,
         u.displayname as owner_name,
         u.reputation as owner_rep,
         ue.rep_band as owner_rep_band,
         u.creationdate as owner_since,
         ue.gold as owner_gold,
         ue.silver as owner_silver,
         ue.bronze as owner_bronze
  from ranked_questions rq
  left join users u on u.id = rq.asker_id
  left join user_enriched ue on ue.user_id = u.id
),
first_answerer as (
  select rq.question_id,
         u.displayname as first_answerer_name,
         u.reputation as first_answerer_rep
  from ranked_questions rq
  left join users u on u.id = rq.first_answerer_id
),
tag_rollup as (
  select te.question_id,
         string_agg(it.tag, ',' order by it.tag) as tags_sorted,
         sum(case when it.popular_qs > 0 then 1 else 0 end) as popular_tag_hits
  from tag_expanded te
  join interesting_tags it on it.tag = te.tag
  group by te.question_id
),
question_quality as (
  select
    rq.question_id,
    rq.hotness_score,
    rq.viewcount,
    rq.q_net_votes,
    rq.total_answers,
    rq.comment_count,
    rq.close_votes,
    rq.duplicate_marks,
    rq.first_is_accepted,
    rq.secs_to_first_answer,
    tr.popular_tag_hits,
    case
      when rq.q_net_votes is null then 'unknown'
      when rq.q_net_votes >= 10 and rq.viewcount >= 5000 then 'excellent'
      when rq.q_net_votes >= 3 and rq.viewcount >= 1000 then 'good'
      when rq.q_net_votes >= 0 then 'ok'
      else 'poor'
    end as quality_band
  from ranked_questions rq
  left join tag_rollup tr on tr.question_id = rq.question_id
),
q_rank as (
  select
    qq.question_id,
    qq.hotness_score,
    qq.quality_band,
    qq.viewcount,
    qq.q_net_votes,
    qq.total_answers,
    qq.comment_count,
    qq.close_votes,
    qq.duplicate_marks,
    qq.first_is_accepted,
    qq.secs_to_first_answer,
    qq.popular_tag_hits,
    dense_rank() over (order by qq.hotness_score desc, qq.viewcount desc) as hot_rank,
    row_number() over (order by qq.q_net_votes desc nulls last, qq.viewcount desc nulls last) as votes_rank,
    percent_rank() over (order by qq.secs_to_first_answer asc nulls last) as speed_pct
  from question_quality qq
),
final as (
  select
    qr.question_id,
    left(coalesce(rq.title, ''), 200) as title_sample,
    coalesce(tr.tags_sorted, '') as interesting_tags,
    coalesce(qo.owner_name, '[unknown]') as owner_name,
    qo.owner_rep,
    qo.owner_rep_band,
    qo.owner_gold,
    qo.owner_silver,
    qo.owner_bronze,
    coalesce(fa.first_answerer_name, '[none]') as first_answerer,
    rq.first_answer_score,
    rq.first_is_accepted,
    rq.total_answers,
    rq.viewcount,
    rq.q_net_votes,
    rq.comment_count,
    rq.close_votes,
    rq.duplicate_marks,
    rq.duplicate_close_reasons,
    rq.q_last_vote_at,
    rq.last_answer_at,
    rq.question_created_at,
    qr.hotness_score,
    qr.quality_band,
    qr.hot_rank,
    qr.votes_rank,
    round(cast(qr.speed_pct as numeric), 4) as speed_pct,
    case
      when rq.viewcount is null or rq.viewcount = 0 then null
      else round((cast(rq.q_net_votes as numeric) / nullif(rq.viewcount,0)) * 1000, 4)
    end as votes_per_1k_views,
    case
      when rq.total_answers = 0 then null
      else round(cast(rq.sum_answer_net_votes as numeric) / nullif(rq.total_answers,0), 4)
    end as avg_answer_votes,
    case
      when rq.secs_to_first_answer is null then 'no answer yet'
      when rq.secs_to_first_answer < 3600 then '<1h'
      when rq.secs_to_first_answer < 86400 then '<1d'
      when rq.secs_to_first_answer < 604800 then '<1w'
      else '>=1w'
    end as first_answer_sla
  from q_rank qr
  join ranked_questions rq on rq.question_id = qr.question_id
  left join tag_rollup tr on tr.question_id = rq.question_id
  left join question_owner qo on qo.question_id = rq.question_id
  left join first_answerer fa on fa.question_id = rq.question_id
  where
    (
      rq.viewcount >= 100
      or (rq.q_net_votes is not null and rq.q_net_votes >= 1)
      or rq.total_answers >= 1
    )
    and coalesce(qo.owner_rep,0) >= 1
)
select *
from final
where
  (
    quality_band in ('excellent','good')
    or (hot_rank <= 100 and votes_rank <= 500)
    or (first_answer_sla in ('<1h','<1d') and duplicate_marks = 0)
  )
  and (interesting_tags is null or lower(interesting_tags) !~ '(homework|list)')
  and (owner_name is not null and length(owner_name) >= 2)
  and ( (timestamp '2024-10-01 12:34:56' - question_created_at) <= interval '5 years' or q_last_vote_at >= (timestamp '2024-10-01 12:34:56' - interval '3 years') )
order by hot_rank, votes_rank
limit 500;