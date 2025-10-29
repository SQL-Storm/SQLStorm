-- {"query": "220.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2739} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
),
user_badge_rollup as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
q as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    p.answercount,
    p.commentcount,
    p.favoritecount
  from posts p
  where p.posttypeid = 1
),
a as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score
  from posts p
  where p.posttypeid = 2
),
question_activity as (
  select
    q.id as question_id,
    q.user_id as asker_id,
    q.creationdate as question_date,
    q.score as question_score,
    q.viewcount,
    q.title,
    q.tags,
    q.acceptedanswerid,
    q.closeddate,
    q.answercount,
    q.commentcount,
    q.favoritecount,
    -- time to first answer
    (select min(a2.creationdate) from a a2 where a2.question_id = q.id) as first_answer_date,
    -- time to accepted answer
    (select p3.creationdate from posts p3 where p3.id = q.acceptedanswerid) as accepted_answer_date,
    -- total answer score
    (select coalesce(sum(a3.score), 0) from a a3 where a3.question_id = q.id) as total_answer_score
  from q
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
comment_rollup as (
  select
    c.postid,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
    max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
dupe_links as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as linked_links,
    min(pl.creationdate) filter (where pl.linktypeid = 3) as first_dupe_link_date
  from postlinks pl
  group by pl.postid
),
closed_reasons as (
  select
    ph.postid as question_id,
    min(ph.creationdate) as first_close_date,
    max(ph.creationdate) as last_close_date,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes,
    max(
      case
        when ph.posthistorytypeid = 10 then
          nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
        else null
      end
    ) as last_close_reason_raw
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
tag_explode as (
  select
    qa.question_id,
    unnest(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><')) as tag
  from question_activity qa
  where qa.tags is not null
),
tag_stats as (
  select
    te.tag,
    count(*) as tag_q_count,
    avg(qa.question_score) as tag_avg_q_score,
    avg(qa.viewcount) as tag_avg_views
  from tag_explode te
  join question_activity qa on qa.question_id = te.question_id
  group by te.tag
),
user_post_stats as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    avg(nullif(p.score,0)) filter (where p.posttypeid = 1) as avg_q_score_nonzero,
    avg(nullif(p.score,0)) filter (where p.posttypeid = 2) as avg_a_score_nonzero,
    sum(p.viewcount) filter (where p.posttypeid = 1) as q_view_sum,
    max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
accepted_answerers as (
  select
    qa.question_id,
    p.owneruserid as accepted_user_id,
    p.score as accepted_answer_score
  from question_activity qa
  join posts p on p.id = qa.acceptedanswerid
),
question_quality as (
  select
    qa.question_id,
    qa.asker_id,
    qa.question_date,
    qa.title,
    qa.viewcount,
    qa.question_score,
    qa.total_answer_score,
    qa.answercount,
    qa.commentcount,
    qa.favoritecount,
    qa.closeddate,
    qa.first_answer_date,
    qa.accepted_answer_date,
    vr.upvotes,
    vr.downvotes,
    vr.favorites,
    vr.bounty_total,
    cr.first_close_date,
    cr.last_close_date,
    cr.close_votes,
    cr.reopen_votes,
    cr.last_close_reason_raw,
    dl.duplicate_links,
    dl.linked_links,
    dl.first_dupe_link_date,
    coalesce(vr.upvotes - vr.downvotes, 0) as net_votes,
    case
      when qa.first_answer_date is not null then extract(epoch from (qa.first_answer_date - qa.question_date)) / 3600.0
      else null
    end as hours_to_first_answer,
    case
      when qa.accepted_answer_date is not null then extract(epoch from (qa.accepted_answer_date - qa.question_date)) / 3600.0
      else null
    end as hours_to_accept,
    case when qa.closeddate is not null then 1 else 0 end as is_closed_flag
  from question_activity qa
  left join votes_rollup vr on vr.postid = qa.question_id
  left join closed_reasons cr on cr.question_id = qa.question_id
  left join dupe_links dl on dl.question_id = qa.question_id
),
ranked_questions as (
  select
    qq.*,
    row_number() over (order by coalesce(qq.net_votes,0) desc, coalesce(qq.viewcount,0) desc, qq.question_date desc) as rank_by_hotness,
    ntile(10) over (order by coalesce(qq.viewcount,0) desc) as view_ntile,
    dense_rank() over (order by coalesce(qq.answercount,0) desc) as dense_by_answers
  from question_quality qq
),
final_agg as (
  select
    rq.question_id,
    rq.asker_id,
    ru.displayname as asker_name,
    ru.reputation as asker_reputation,
    coalesce(ru.location, 'unknown') as asker_location,
    coalesce(ru.websiteurl, 'n/a') as asker_website,
    ubs.badge_count,
    ubs.gold_count,
    ubs.silver_count,
    ubs.bronze_count,
    ups.q_count,
    ups.a_count,
    ups.avg_q_score_nonzero,
    ups.avg_a_score_nonzero,
    ups.q_view_sum,
    ups.last_post_date,
    rq.title,
    rq.viewcount,
    rq.question_score,
    rq.total_answer_score,
    rq.answercount,
    rq.commentcount,
    rq.favoritecount,
    rq.net_votes,
    rq.bounty_total,
    rq.is_closed_flag,
    rq.first_close_date,
    rq.last_close_date,
    rq.close_votes,
    rq.reopen_votes,
    rq.duplicate_links,
    rq.linked_links,
    rq.first_dupe_link_date,
    rq.hours_to_first_answer,
    rq.hours_to_accept,
    rq.rank_by_hotness,
    rq.view_ntile,
    rq.dense_by_answers,
    aa.accepted_user_id,
    aa.accepted_answer_score,
    case
      when aa.accepted_user_id = rq.asker_id then 'self-answered'
      when aa.accepted_user_id is null then 'no-accept'
      else 'accepted-by-others'
    end as acceptance_type,
    (select string_agg(te.tag, ',' order by ts.tag_q_count desc, ts.tag_avg_q_score desc)
     from tag_explode te
     join tag_stats ts on ts.tag = te.tag
     where te.question_id = rq.question_id) as tags_enriched
  from ranked_questions rq
  left join recent_users ru on ru.user_id = rq.asker_id
  left join user_badge_rollup ubs on ubs.userid = rq.asker_id
  left join user_post_stats ups on ups.user_id = rq.asker_id
  left join accepted_answerers aa on aa.question_id = rq.question_id
)
select
  fa.question_id,
  fa.title,
  fa.asker_id,
  fa.asker_name,
  fa.asker_reputation,
  fa.asker_location,
  fa.badge_count,
  fa.gold_count,
  fa.silver_count,
  fa.bronze_count,
  fa.q_count,
  fa.a_count,
  fa.viewcount,
  fa.question_score,
  fa.total_answer_score,
  fa.net_votes,
  fa.bounty_total,
  fa.answercount,
  fa.commentcount,
  fa.favoritecount,
  fa.is_closed_flag,
  fa.close_votes,
  fa.reopen_votes,
  fa.hours_to_first_answer,
  fa.hours_to_accept,
  fa.rank_by_hotness,
  fa.view_ntile,
  fa.dense_by_answers,
  fa.acceptance_type,
  coalesce(nullif(fa.tags_enriched, ''), '(untagged)') as tags_enriched,
  -- complicated predicate projection for benchmarking:
  case
    when fa.bounty_total > 0 and fa.net_votes > 10 and (fa.is_closed_flag = 0 or fa.reopen_votes > 0) then 'high-value'
    when fa.net_votes < 0 and fa.answercount = 0 and fa.viewcount < 50 then 'low-engagement'
    when fa.close_votes > fa.reopen_votes and fa.is_closed_flag = 1 then 'controversial-closed'
    else 'normal'
  end as engagement_bucket,
  -- correlated scalar subquery with null logic
  coalesce((
    select avg(a4.score)
    from a a4
    where a4.question_id = fa.question_id
      and a4.user_id <> fa.asker_id
  ), 0) as avg_non_asker_answer_score
from final_agg fa
where
  (
    fa.rank_by_hotness <= 1000
    or (fa.view_ntile in (1,2) and fa.net_votes >= 0)
    or (fa.is_closed_flag = 1 and coalesce(fa.close_votes,0) >= 1)
  )
  and (
    fa.asker_reputation >= 1
    and (fa.badge_count is null or fa.badge_count >= 0)
  )
order by
  fa.rank_by_hotness,
  fa.viewcount desc,
  fa.question_id
limit 500;