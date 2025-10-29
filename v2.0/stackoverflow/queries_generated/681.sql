-- {"query": "681.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2938} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select p.id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.closeddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select a.id,
         a.parentid as question_id,
         a.owneruserid,
         a.creationdate,
         a.score
  from posts a
  where a.posttypeid = 2
),
q_activity as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as question_created,
         q.score as question_score,
         q.viewcount,
         q.acceptedanswerid,
         q.closeddate,
         count(distinct a.id) as answer_count,
         max(a.score) filter (where a.id is not null) as max_answer_score,
         avg(a.score::numeric) filter (where a.id is not null) as avg_answer_score,
         min(a.creationdate) filter (where a.id is not null) as first_answer_at
  from question_posts q
  left join answer_posts a
    on a.question_id = q.id
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.acceptedanswerid, q.closeddate
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         count(*) as total_votes,
         count(*) filter (where v.creationdate >= now() - interval '90 days') as recent_votes_90d
  from votes v
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_at,
         sum(case when c.score > 0 then 1 else 0 end) as pos_comments
  from comments c
  group by c.postid
),
tag_expanded as (
  select q.id as question_id,
         lower(trim(t.tag)) as tag
  from question_posts q
  cross join lateral unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as t(tag)
),
tag_stats as (
  select te.question_id,
         count(*) as tag_count,
         string_agg(te.tag, ',' order by te.tag) as tag_list
  from tag_expanded te
  group by te.question_id
),
badges_agg as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) as total_badges,
         count(*) filter (where b.date >= now() - interval '365 days') as badges_past_year
  from badges b
  group by b.userid
),
post_history_flags as (
  select ph.postid,
         max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
         max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
         max(case when ph.posthistorytypeid in (50) then 1 else 0 end) as was_bumped,
         max(case when ph.posthistorytypeid in (52) then 1 else 0 end) as was_hot
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select pl.postid as duplicate_id,
         pl.relatedpostid as original_id,
         min(pl.creationdate) as first_dup_link_at
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
asker_quality as (
  select u.id as user_id,
         percentile_cont(0.5) within group (order by p.score) as median_q_score,
         avg(p.viewcount::numeric) as avg_q_views,
         sum(case when qa.answer_count > 0 then 1 else 0 end)::numeric / nullif(count(*),0) as pct_answered
  from users u
  join posts p on p.owneruserid = u.id and p.posttypeid = 1
  left join q_activity qa on qa.question_id = p.id
  group by u.id
),
answerer_quality as (
  select u.id as user_id,
         avg(a.score::numeric) as avg_a_score,
         count(*) filter (where a.score > 0) as pos_answers,
         count(*) as total_answers
  from users u
  join posts a on a.owneruserid = u.id and a.posttypeid = 2
  group by u.id
),
question_rank as (
  select qa.question_id,
         qa.asker_id,
         qa.question_created,
         qa.question_score,
         qa.viewcount,
         qa.answer_count,
         qa.max_answer_score,
         qa.avg_answer_score,
         qa.first_answer_at,
         va.upvotes,
         va.downvotes,
         va.favorites,
         va.total_votes,
         ca.comment_count,
         coalesce(ts.tag_count, 0) as tag_count,
         coalesce(ts.tag_list, '') as tag_list,
         ph.was_closed_or_migrated,
         ph.was_reopened,
         ph.was_bumped,
         ph.was_hot,
         dl.original_id as duplicate_of,
         dl.first_dup_link_at,
         case
           when qa.acceptedanswerid is not null then 1
           when exists (select 1 from answersub a2 where 1=0) then 0
           else 0
         end as has_accepted_answer_flag
  from q_activity qa
  left join vote_agg va on va.postid = qa.question_id
  left join comment_agg ca on ca.postid = qa.question_id
  left join tag_stats ts on ts.question_id = qa.question_id
  left join post_history_flags ph on ph.postid = qa.question_id
  left join dup_links dl on dl.duplicate_id = qa.question_id
),
user_enriched as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate as user_created,
         coalesce(ru.location, 'unknown') as location,
         ru.websiteurl_norm,
         ba.gold_badges,
         ba.silver_badges,
         ba.bronze_badges,
         ba.total_badges,
         ba.badges_past_year,
         aq.median_q_score,
         aq.avg_q_views,
         aq.pct_answered,
         anq.avg_a_score,
         anq.pos_answers,
         anq.total_answers
  from recent_users ru
  left join badges_agg ba on ba.userid = ru.user_id
  left join asker_quality aq on aq.user_id = ru.user_id
  left join answerer_quality anq on anq.user_id = ru.user_id
),
q_with_users as (
  select qr.*,
         ue.displayname as asker_name,
         ue.reputation as asker_reputation,
         ue.total_badges as asker_total_badges,
         ue.pct_answered as asker_pct_answered
  from question_rank qr
  left join user_enriched ue on ue.user_id = qr.asker_id
),
scored as (
  select
    qwu.question_id,
    qwu.asker_id,
    qwu.asker_name,
    qwu.asker_reputation,
    qwu.asker_total_badges,
    qwu.question_created,
    qwu.viewcount,
    qwu.answer_count,
    qwu.tag_count,
    qwu.tag_list,
    qwu.was_closed_or_migrated,
    qwu.was_reopened,
    qwu.was_hot,
    qwu.duplicate_of,
    qwu.first_dup_link_at,
    qwu.upvotes,
    qwu.downvotes,
    qwu.favorites,
    qwu.total_votes,
    qwu.comment_count,
    qwu.max_answer_score,
    qwu.avg_answer_score,
    qwu.first_answer_at,
    qwu.asker_pct_answered,
    case
      when qwu.was_closed_or_migrated = 1 then -100
      else 0
    end
    + coalesce(least(qwu.viewcount, 10000) / 10, 0)
    + coalesce(qwu.upvotes * 5 - qwu.downvotes * 4, 0)
    + coalesce(qwu.favorites * 3, 0)
    + coalesce(qwu.answer_count * 7, 0)
    + coalesce(greatest(qwu.max_answer_score, 0) * 2, 0)
    + coalesce((case when qwu.comment_count > 10 then 10 else qwu.comment_count end), 0)
    + coalesce((case when qwu.tag_count between 2 and 5 then 5 when qwu.tag_count = 1 then 1 else 0 end), 0)
    + coalesce((qwu.asker_reputation / 1000), 0)
    + coalesce(round(100 * qwu.asker_pct_answered), 0)
    as hotness_score
  from q_with_users qwu
),
ranked as (
  select s.*,
         row_number() over (order by s.hotness_score desc, s.viewcount desc, s.total_votes desc, s.question_id) as rn,
         rank() over (order by s.hotness_score desc) as rnk_hot,
         dense_rank() over (partition by (case when s.was_hot = 1 then 'was_hot' else 'other' end) order by s.hotness_score desc) as drnk_by_hotflag,
         avg(s.hotness_score) over () as avg_hotness_all,
         avg(s.hotness_score) over (partition by (s.tag_count > 0)) as avg_hotness_has_tags,
         lag(s.hotness_score) over (order by s.hotness_score desc) as prev_score,
         lead(s.hotness_score) over (order by s.hotness_score desc) as next_score
  from scored s
),
recent_vs_old as (
  select r.*,
         case when r.question_created >= now() - interval '30 days' then 'recent_30d' else 'older' end as recency_bucket
  from ranked r
),
final as (
  select
    rv.question_id,
    rv.asker_id,
    coalesce(rv.asker_name, concat('user#', rv.asker_id::text)) as asker_name,
    rv.asker_reputation,
    rv.asker_total_badges,
    rv.question_created,
    rv.viewcount,
    rv.answer_count,
    rv.tag_count,
    rv.tag_list,
    rv.was_closed_or_migrated,
    rv.was_reopened,
    rv.was_hot,
    rv.duplicate_of,
    rv.first_dup_link_at,
    rv.upvotes,
    rv.downvotes,
    rv.favorites,
    rv.total_votes,
    rv.comment_count,
    rv.max_answer_score,
    rv.avg_answer_score,
    rv.first_answer_at,
    rv.hotness_score,
    rv.rn,
    rv.rnk_hot,
    rv.drnk_by_hotflag,
    rv.avg_hotness_all,
    rv.avg_hotness_has_tags,
    rv.prev_score,
    rv.next_score,
    rv.recency_bucket,
    case
      when rv.duplicate_of is not null then 'duplicate'
      when rv.was_closed_or_migrated = 1 then 'closed/migrated'
      when rv.was_hot = 1 then 'hot'
      else 'normal'
    end as status_bucket
  from recent_vs_old rv
)
select *
from final f
where
  -- complex predicate mixing null logic, pattern search, scalar subqueries, and set operators
  coalesce(f.upvotes, 0) - coalesce(f.downvotes, 0) >= (
    select floor(avg(coalesce(upvotes,0) - coalesce(downvotes,0))::numeric)
    from ranked
  )
  and (
    f.tag_count is null
    or f.tag_count between 2 and 7
    or exists (
      select 1
      from tag_expanded te
      where te.question_id = f.question_id
        and (te.tag like '%sql%' or te.tag similar to '(perf|bench|optimiz)%')
    )
  )
  and not exists (
    select 1
    from posthistory ph
    where ph.postid = f.question_id
      and ph.posthistorytypeid in (12) -- deleted
  )
  and (f.was_closed_or_migrated = 0 or f.was_reopened = 1 or f.status_bucket <> 'closed/migrated')
  and f.hotness_score > coalesce(f.avg_hotness_has_tags, f.avg_hotness_all, 0)
order by f.hotness_score desc, f.viewcount desc, f.total_votes desc
limit 250;