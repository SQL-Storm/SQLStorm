-- {"query": "976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3057} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    case when u.websiteurl ~* '^(https?://)?(www\.)?github\.com' then 1 else 0 end as has_github,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_badge_rollup as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
question_core as (
  select
    p.id as question_id,
    p.owneruserid as owner_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    p.closeddate,
    p.acceptedanswerid,
    case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
),
answer_core as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as owner_id,
    a.creationdate,
    a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
first_answer_per_question as (
  select distinct on (ac.question_id)
    ac.question_id,
    ac.answer_id as first_answer_id,
    ac.owner_id as first_answer_user_id,
    ac.creationdate as first_answer_date,
    ac.answer_score as first_answer_score
  from answer_core ac
  order by ac.question_id, ac.creationdate asc, ac.answer_id asc
),
votes_rollup as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    min(case when v.votetypeid in (8,9) then v.creationdate end) as first_bounty_date
  from votes v
  group by v.postid
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.score) as max_comment_score,
    sum(case when c.score >= 5 then 1 else 0 end) as high_scoring_comments
  from comments c
  group by c.postid
),
dup_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
close_reasons as (
  select
    ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
  from posthistory ph
  group by ph.postid
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from question_core q
  where q.tags is not null and q.tags like '<%>'
),
tag_quality as (
  select
    te.question_id,
    avg(t.count) as avg_tag_popularity,
    sum(case when t.ismoderatoronly = 1 then 1 else 0 end) as mod_only_tags,
    sum(case when t.isrequired = 1 then 1 else 0 end) as required_tags
  from tag_expansion te
  left join tags t on lower(t.tagname) = lower(te.tagname)
  group by te.question_id
),
owner_activity as (
  select
    q.owner_id,
    count(*) filter (where q.is_closed = 1) as closed_questions,
    count(*) filter (where q.is_closed = 0) as open_questions,
    avg(nullif(q.score,0)) as avg_question_score_nonzero,
    sum(coalesce(vr.upvotes,0)) as total_question_upvotes,
    sum(coalesce(vr.downvotes,0)) as total_question_downvotes
  from question_core q
  left join votes_rollup vr on vr.postid = q.question_id
  group by q.owner_id
),
accepted_answer_info as (
  select
    q.question_id,
    aa.id as accepted_answer_id,
    aa.owneruserid as accepted_answer_owner_id,
    aa.creationdate as accepted_answer_date,
    aa.score as accepted_answer_score
  from question_core q
  left join posts aa on aa.id = q.acceptedanswerid
),
question_activity_window as (
  select
    q.question_id,
    q.creationdate,
    q.owner_id,
    q.score,
    q.viewcount,
    q.answercount,
    lag(q.creationdate) over (partition by q.owner_id order by q.creationdate) as prev_question_date,
    lead(q.creationdate) over (partition by q.owner_id order by q.creationdate) as next_question_date,
    sum(q.viewcount) over (partition by q.owner_id order by q.creationdate rows between 5 preceding and current row) as rolling_views_6,
    avg(q.score) over (partition by q.owner_id order by q.creationdate rows between 5 preceding and current row) as rolling_score_6
  from question_core q
),
ranked_questions as (
  select
    qaw.*,
    dense_rank() over (order by coalesce(qaw.viewcount,0) desc, coalesce(qaw.score,0) desc, qaw.creationdate desc) as global_popularity_rank,
    row_number() over (partition by qaw.owner_id order by coalesce(qaw.viewcount,0) desc, coalesce(qaw.score,0) desc, qaw.creationdate desc) as per_user_rank
  from question_activity_window qaw
),
owner_join as (
  select
    q.question_id,
    u.id as owner_id,
    u.displayname as owner_name,
    u.reputation as owner_reputation,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ra.has_github as owner_has_github,
    ra.location_norm as owner_location
  from question_core q
  left join users u on u.id = q.owner_id
  left join user_badge_rollup ub on ub.userid = u.id
  left join recent_users ra on ra.user_id = u.id
),
scored as (
  select
    rq.question_id,
    rq.owner_id,
    oj.owner_name,
    oj.owner_reputation,
    oj.total_badges,
    oj.gold_badges,
    oj.silver_badges,
    oj.bronze_badges,
    oj.owner_has_github,
    oj.owner_location,
    rq.creationdate,
    rq.prev_question_date,
    rq.next_question_date,
    rq.viewcount,
    rq.score,
    rq.answercount,
    coalesce(vr.upvotes,0) as upvotes,
    coalesce(vr.downvotes,0) as downvotes,
    coalesce(vr.favorites,0) as favorites,
    coalesce(vr.bounty_total,0) as bounty_total,
    cs.comment_count,
    cs.max_comment_score,
    cs.high_scoring_comments,
    dr.duplicate_links,
    dr.related_links,
    cr.last_closed_date,
    cr.last_close_reason_raw,
    coalesce(tq.avg_tag_popularity,0) as avg_tag_popularity,
    coalesce(tq.mod_only_tags,0) as mod_only_tags,
    coalesce(tq.required_tags,0) as required_tags,
    fa.first_answer_id,
    fa.first_answer_user_id,
    fa.first_answer_date,
    fa.first_answer_score,
    ai.accepted_answer_id,
    ai.accepted_answer_owner_id,
    ai.accepted_answer_date,
    ai.accepted_answer_score,
    rq.rolling_views_6,
    rq.rolling_score_6,
    rq.global_popularity_rank,
    rq.per_user_rank,
    case
      when ai.accepted_answer_id is not null then 1
      when fa.first_answer_id is not null and rq.answercount > 0 then 0
      else null
    end as has_accepted_binary,
    case
      when cr.last_close_reason_raw ~ '^\d+$' then cr.last_close_reason_raw
      else null
    end as last_close_reason_code_str,
    case
      when rq.viewcount is null or rq.viewcount = 0 then null
      else round((coalesce(vr.upvotes,0)::numeric - coalesce(vr.downvotes,0)::numeric) / nullif(rq.viewcount::numeric,0), 6)
    end as vote_view_ratio,
    case
      when rq.answercount is null or rq.answercount = 0 then null
      else round(coalesce(vr.upvotes,0)::numeric / rq.answercount::numeric, 6)
    end as upvotes_per_answer
  from ranked_questions rq
  left join votes_rollup vr on vr.postid = rq.question_id
  left join comment_stats cs on cs.postid = rq.question_id
  left join dup_links dr on dr.postid = rq.question_id
  left join close_reasons cr on cr.postid = rq.question_id
  left join tag_quality tq on tq.question_id = rq.question_id
  left join first_answer_per_question fa on fa.question_id = rq.question_id
  left join accepted_answer_info ai on ai.question_id = rq.question_id
  left join owner_join oj on oj.question_id = rq.question_id
),
close_reason_lkp as (
  select crt.id::varchar as reason_code, crt.name as reason_name
  from closereasontypes crt
),
final_enriched as (
  select
    s.*,
    coalesce(crl.reason_name, 'Unknown/Legacy') as last_close_reason_name,
    case
      when s.accepted_answer_owner_id = s.owner_id then 'self-accepted'
      when s.accepted_answer_owner_id is null then 'no-accept'
      else 'accepted-by-other'
    end as acceptance_type,
    case
      when s.owner_reputation >= 200000 then 'Legend'
      when s.owner_reputation >= 50000 then 'Veteran'
      when s.owner_reputation >= 10000 then 'Experienced'
      when s.owner_reputation >= 2000 then 'Intermediate'
      when s.owner_reputation is null then 'Unknown'
      else 'Newbie'
    end as owner_rep_bucket
  from scored s
  left join close_reason_lkp crl on crl.reason_code = s.last_close_reason_code_str
),
time_filtered as (
  select fe.*
  from final_enriched fe
  where fe.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts where posttypeid = 1)
)
select
  tf.question_id,
  coalesce(tf.owner_name, '[unknown]') as owner_name,
  tf.owner_rep_bucket,
  tf.total_badges,
  tf.gold_badges,
  tf.silver_badges,
  tf.bronze_badges,
  tf.owner_location,
  tf.owner_has_github,
  tf.creationdate,
  tf.prev_question_date,
  tf.next_question_date,
  tf.viewcount,
  tf.score,
  tf.answercount,
  tf.upvotes,
  tf.downvotes,
  tf.favorites,
  tf.bounty_total,
  tf.comment_count,
  tf.max_comment_score,
  tf.high_scoring_comments,
  tf.duplicate_links,
  tf.related_links,
  tf.avg_tag_popularity,
  tf.mod_only_tags,
  tf.required_tags,
  tf.has_accepted_binary,
  tf.acceptance_type,
  tf.accepted_answer_id,
  tf.accepted_answer_score,
  tf.first_answer_id,
  tf.first_answer_score,
  tf.last_closed_date,
  tf.last_close_reason_name,
  tf.vote_view_ratio,
  tf.upvotes_per_answer,
  tf.rolling_views_6,
  tf.rolling_score_6,
  tf.global_popularity_rank,
  tf.per_user_rank,
  case
    when tf.global_popularity_rank <= 100 then 'Top 100'
    when tf.global_popularity_rank <= 1000 then 'Top 1k'
    else 'Long tail'
  end as popularity_bucket
from time_filtered tf
where (
    tf.accepted_answer_id is not null
    or (tf.answercount >= 3 and tf.upvotes - tf.downvotes >= 5)
    or (tf.bounty_total > 0)
  )
and coalesce(tf.viewcount,0) > 0
and (
    tf.last_close_reason_name is null
    or tf.last_close_reason_name not ilike '%duplicate%'
  )
qualify row_number() over (
  partition by tf.owner_id
  order by tf.global_popularity_rank asc, tf.vote_view_ratio desc nulls last, tf.creationdate desc
) <= 50
order by tf.global_popularity_rank, tf.owner_id, tf.creationdate desc;