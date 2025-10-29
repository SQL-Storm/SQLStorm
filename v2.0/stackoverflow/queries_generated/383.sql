-- {"query": "383.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3463} 
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.owneruserid,
    p.acceptedanswerid,
    p.parentid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.lastactivitydate,
    u.reputation,
    u.displayname,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_guess
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_split as (
  select
    rp.id as post_id,
    lower(trim(tag)) as tag
  from recent_posts rp
  cross join lateral unnest(
    case
      when rp.tags is null then array['']
      else string_to_array(substring(rp.tags, 2, length(rp.tags) - 2), '><')
    end
  ) as t(tag)
),
question_core as (
  select
    rp.*,
    case when rp.posttypeid = 1 then 1 else 0 end as is_question,
    case when rp.posttypeid = 2 then 1 else 0 end as is_answer
  from recent_posts rp
),
answer_to_question as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_user_id,
    a.creationdate as answer_created,
    a.score as answer_score
  from question_core a
  where a.is_answer = 1
),
question_stats as (
  select
    q.id as question_id,
    q.title,
    q.creationdate as question_created,
    q.owneruserid as question_user_id,
    q.score as question_score,
    q.viewcount as question_views,
    q.acceptedanswerid,
    count(a.answer_id) filter (where a.answer_id is not null) as answer_count,
    max(a.answer_score) filter (where a.answer_id is not null) as max_answer_score,
    min(a.answer_score) filter (where a.answer_id is not null) as min_answer_score,
    avg(a.answer_score) filter (where a.answer_id is not null) as avg_answer_score
  from question_core q
  left join answer_to_question a on a.question_id = q.id
  where q.is_question = 1
  group by q.id, q.title, q.creationdate, q.owneruserid, q.score, q.viewcount, q.acceptedanswerid
),
activity_windows as (
  select
    rp.id as post_id,
    rp.posttypeid,
    rp.creationdate,
    rp.owneruserid,
    rp.score,
    rp.viewcount,
    rp.lastactivitydate,
    row_number() over (partition by rp.owneruserid order by rp.creationdate desc) as rn_by_user_newest,
    rank() over (order by rp.score desc nulls last) as score_rank_global,
    dense_rank() over (partition by rp.posttypeid order by rp.viewcount desc nulls last) as view_rank_by_type,
    sum(coalesce(rp.score,0)) over (partition by rp.owneruserid order by rp.creationdate rows between unbounded preceding and current row) as running_user_score
  from recent_posts rp
),
comment_aggs as (
  select
    c.postid,
    count(*) as comment_count,
    sum(c.score) as comment_score_sum,
    max(c.score) as comment_score_max,
    min(c.score) as comment_score_min,
    avg(c.score) as comment_score_avg,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
  group by c.postid
),
vote_aggs as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as total_votes,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by v.postid
),
edit_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    count(*) filter (where ph.posthistorytypeid = 12) as delete_events,
    count(*) filter (where ph.posthistorytypeid = 13) as undelete_events,
    max(ph.creationdate) as last_history_date,
    max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_raw
  from posthistory ph
  where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
  group by ph.postid
),
close_reason_normalized as (
  select
    e.postid,
    cr.name as last_close_reason_name
  from edit_events e
  left join closereasontypes cr
    on cr.id = e.last_close_reason_raw
),
link_stats as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_out_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_of_count,
    count(*) as total_links,
    max(pl.creationdate) as last_link_date
  from postlinks pl
  where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
  group by pl.postid
),
tag_popularity as (
  select
    ts.tag,
    count(distinct ts.post_id) as posts_with_tag,
    sum(qs.answer_count) filter (where qs.question_id is not null) as total_answers_on_tag,
    avg(qs.question_views) filter (where qs.question_id is not null) as avg_views_on_tag
  from tag_split ts
  left join question_stats qs on qs.question_id = ts.post_id
  where ts.tag <> ''
  group by ts.tag
),
user_badges as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    max(b.date) as last_badge_date
  from badges b
  where b.date >= (select max(date) - interval '365 days' from badges)
  group by b.userid
),
normalized_titles as (
  select
    qs.question_id,
    regexp_replace(coalesce(qs.title,''), '\s+', ' ', 'g') as title_clean,
    length(coalesce(qs.title,'')) as title_len,
    position('how' in lower(coalesce(qs.title,''))) > 0 as has_how,
    position('why' in lower(coalesce(qs.title,''))) > 0 as has_why
  from question_stats qs
),
accepted_answer_latency as (
  select
    qs.question_id,
    extract(epoch from (a.creationdate - qs.question_created))::bigint as seconds_to_first_answer,
    extract(epoch from (aa.creationdate - qs.question_created))::bigint as seconds_to_accepted_answer
  from question_stats qs
  left join posts aa on aa.id = qs.acceptedanswerid
  left join lateral (
    select p.creationdate
    from posts p
    where p.parentid = qs.question_id and p.posttypeid = 2
    order by p.creationdate
    limit 1
  ) a on true
),
user_activity as (
  select
    rp.owneruserid as user_id,
    count(*) as posts_in_year,
    sum(case when rp.posttypeid = 1 then 1 else 0 end) as questions_in_year,
    sum(case when rp.posttypeid = 2 then 1 else 0 end) as answers_in_year,
    max(rp.creationdate) as last_post_date
  from recent_posts rp
  where rp.owneruserid is not null
  group by rp.owneruserid
),
post_quality_score as (
  select
    q.question_id,
    coalesce(0.4 * log(1 + greatest(q.question_views,0))
           + 0.6 * coalesce(q.question_score,0)
           + 0.2 * coalesce(va.upvotes - va.downvotes, 0)
           + 0.1 * coalesce(ca.comment_score_sum, 0)
           - 0.3 * coalesce(va.downvotes, 0)
           + 0.2 * coalesce(ls.linked_out_count, 0)
           - 0.5 * coalesce(ls.duplicate_of_count, 0)
           + 0.15 * coalesce(q.answer_count, 0)
           + 0.25 * coalesce(q.max_answer_score, 0), 0) as quality_score
  from question_stats q
  left join vote_aggs va on va.postid = q.question_id
  left join comment_aggs ca on ca.postid = q.question_id
  left join link_stats ls on ls.postid = q.question_id
),
tagged_quality as (
  select
    ts.post_id as question_id,
    ts.tag,
    pq.quality_score,
    row_number() over (partition by ts.post_id order by pq.quality_score desc nulls last, ts.tag) as rn
  from tag_split ts
  join post_quality_score pq on pq.question_id = ts.post_id
  where ts.tag <> ''
),
dominant_tag as (
  select
    tq.question_id,
    min(tq.tag) filter (where tq.rn = 1) as dominant_tag
  from tagged_quality tq
  group by tq.question_id
),
user_reputation_bucket as (
  select
    u.id as user_id,
    case
      when u.reputation >= 100000 then 'Legend'
      when u.reputation >= 25000 then 'Guru'
      when u.reputation >= 5000 then 'Experienced'
      when u.reputation >= 1000 then 'Intermediate'
      when u.reputation >= 100 then 'Beginner'
      else 'Newbie'
    end as rep_bucket
  from users u
),
final_join as (
  select
    qs.question_id,
    qs.title,
    nt.title_len,
    qs.question_score,
    qs.question_views,
    qs.answer_count,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.comment_score_sum,0) as comment_score_sum,
    coalesce(e.edit_count,0) as edit_count,
    coalesce(e.close_events,0) as close_events,
    coalesce(e.reopen_events,0) as reopen_events,
    coalesce(e.delete_events,0) as delete_events,
    crn.last_close_reason_name,
    coalesce(ls.linked_out_count,0) as linked_out_count,
    coalesce(ls.duplicate_of_count,0) as duplicate_of_count,
    aw.score_rank_global,
    aw.view_rank_by_type,
    aw.running_user_score,
    pq.quality_score,
    dtag.dominant_tag,
    ap.seconds_to_first_answer,
    ap.seconds_to_accepted_answer,
    u.displayname as owner_displayname,
    u.reputation as owner_reputation,
    urb.rep_bucket,
    coalesce(ub.badge_count,0) as badge_count,
    coalesce(ub.gold_count,0) as gold_count,
    coalesce(ub.silver_count,0) as silver_count,
    coalesce(ub.bronze_count,0) as bronze_count,
    ua.posts_in_year,
    ua.questions_in_year,
    ua.answers_in_year,
    rp.country_guess,
    greatest(coalesce(va.last_vote_date, timestamp 'epoch'),
             coalesce(ca.last_comment_date, timestamp 'epoch'),
             coalesce(e.last_history_date, timestamp 'epoch'),
             coalesce(ls.last_link_date, timestamp 'epoch'),
             qs.question_created) as last_interaction
  from question_stats qs
  left join vote_aggs va on va.postid = qs.question_id
  left join comment_aggs ca on ca.postid = qs.question_id
  left join edit_events e on e.postid = qs.question_id
  left join close_reason_normalized crn on crn.postid = qs.question_id
  left join link_stats ls on ls.postid = qs.question_id
  left join activity_windows aw on aw.post_id = qs.question_id
  left join post_quality_score pq on pq.question_id = qs.question_id
  left join dominant_tag dtag on dtag.question_id = qs.question_id
  left join accepted_answer_latency ap on ap.question_id = qs.question_id
  left join recent_posts rp on rp.id = qs.question_id
  left join users u on u.id = qs.question_user_id
  left join user_badges ub on ub.userid = qs.question_user_id
  left join user_activity ua on ua.user_id = qs.question_user_id
  left join normalized_titles nt on nt.question_id = qs.question_id
  left join user_reputation_bucket urb on urb.user_id = qs.question_user_id
),
ranked as (
  select
    f.*,
    ntile(20) over (order by coalesce(f.quality_score, -1e9) desc) as quality_ventile,
    row_number() over (order by f.quality_score desc nulls last) as global_rownum,
    row_number() over (partition by f.dominant_tag order by f.quality_score desc nulls last) as tag_rownum
  from final_join f
)
select
  r.question_id,
  r.title,
  r.dominant_tag,
  r.owner_displayname,
  r.owner_reputation,
  r.rep_bucket,
  r.question_score,
  r.question_views,
  r.answer_count,
  r.upvotes,
  r.downvotes,
  r.favorites,
  r.bounty_total,
  r.comment_count,
  r.edit_count,
  r.close_events,
  coalesce(r.last_close_reason_name, 'N/A') as last_close_reason_name,
  r.linked_out_count,
  r.duplicate_of_count,
  r.quality_score,
  r.quality_ventile,
  r.global_rownum,
  r.tag_rownum,
  r.seconds_to_first_answer,
  r.seconds_to_accepted_answer,
  r.last_interaction,
  r.country_guess
from ranked r
where
  r.quality_score is not null
  and (r.close_events = 0 or r.last_close_reason_name not in ('Duplicate'))
  and (r.seconds_to_first_answer is null or r.seconds_to_first_answer >= 0)
  and (r.title is not null and length(r.title) >= 10)
  and (
    r.owner_reputation is null
    or r.owner_reputation >= coalesce((select avg(reputation) from users), 0) * 0.05
  )
order by
  r.quality_ventile asc,
  r.tag_rownum asc,
  r.global_rownum asc
limit 500;