-- {"query": "38031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2640} 
with recent_active_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         u.location,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(distinct date_trunc('day', p.creationdate)) as post_active_days,
         count(distinct date_trunc('day', c.creationdate)) as comment_active_days
  from users u
  left join badges b on b.userid = u.id
  left join posts p on p.owneruserid = u.id
                     and p.creationdate >= now() - interval '365 days'
  left join comments c on c.userid = u.id
                         and c.creationdate >= now() - interval '365 days'
  where u.creationdate <= now() - interval '30 days'
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location
),
posts_window as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.tags,
    p.title,
    lag(p.score) over (partition by p.owneruserid order by p.creationdate) as prev_score,
    lead(p.score) over (partition by p.owneruserid order by p.creationdate) as next_score,
    row_number() over (partition by p.owneruserid order by p.creationdate desc) as rn_recent,
    row_number() over (partition by p.owneruserid order by p.score desc) as rn_topscore
  from posts p
  where p.creationdate >= now() - interval '730 days'
    and p.posttypeid in (1,2)
),
engagement as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    avg(nullif(p.score,0)) filter (where p.posttypeid = 1) as avg_q_score_nonzero,
    avg(nullif(p.score,0)) filter (where p.posttypeid = 2) as avg_a_score_nonzero,
    percentile_cont(0.5) within group (order by p.score) as median_score,
    sum(p.viewcount) as total_views,
    sum(p.commentcount) as total_post_comments,
    sum(p.favoritecount) as total_favorites,
    count(*) filter (where p.rn_recent <= 5) as recent5_posts,
    max(case when p.rn_topscore = 1 then p.id end) as top_post_id
  from posts_window p
  group by p.owneruserid
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  where v.creationdate >= now() - interval '730 days'
  group by v.postid
),
comment_agg as (
  select
    c.postid,
    count(*) as comment_count_2y,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= now() - interval '730 days'
  group by c.postid
),
link_agg as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count
  from postlinks pl
  where pl.creationdate >= now() - interval '730 days'
  group by pl.postid
),
tag_expansion as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '730 days'
    and p.tags is not null
),
tag_stats as (
  select
    te.post_id,
    count(*) as tag_count,
    sum(case when t.isrequired then 1 else 0 end) as required_tags,
    sum(case when t.ismoderatoronly then 1 else 0 end) as moderator_only_tags,
    avg(t.count) as avg_tag_global_count,
    max(t.count) as max_tag_global_count
  from tag_expansion te
  left join tags t on t.tagname = te.tagname
  group by te.post_id
),
history_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_count,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    count(*) filter (where ph.posthistorytypeid = 12) as delete_events,
    count(*) filter (where ph.posthistorytypeid = 13) as undelete_events,
    min(ph.creationdate) as first_event,
    max(ph.creationdate) as last_event
  from posthistory ph
  where ph.creationdate >= now() - interval '730 days'
  group by ph.postid
),
accepted_map as (
  select
    q.id as question_id,
    q.acceptedanswerid as accepted_id,
    a.owneruserid as accepted_owner_id
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
),
answer_stats as (
  select
    a.parentid as question_id,
    count(*) as answer_count_total,
    avg(a.score) as avg_answer_score,
    max(a.score) as max_answer_score,
    percentile_cont(0.9) within group (order by a.score) as p90_answer_score
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '730 days'
  group by a.parentid
),
hotness as (
  select
    p.id as post_id,
    0.5 * coalesce(va.upvotes,0) - 0.7 * coalesce(va.downvotes,0)
      + 0.0005 * coalesce(p.viewcount,0)
      + 2.0 * (case when ph.close_votes_events > 0 then -1 else 0 end)
      + 1.5 * (case when p.answercount >= 1 then 1 else 0 end)
      + 0.3 * coalesce(ca.comment_count_2y,0)
      + 0.2 * coalesce(la.linked_count,0)
      - 1.0 * coalesce(la.duplicate_count,0)
      + 0.1 * coalesce(ts.tag_count,0)
      - 0.2 * coalesce(ts.moderator_only_tags,0)
      + 0.0001 * coalesce(va.bounty_started,0)
      + 0.0002 * coalesce(va.bounty_awarded,0)
      as hotness_score
  from posts p
  left join vote_agg va on va.postid = p.id
  left join comment_agg ca on ca.postid = p.id
  left join link_agg la on la.postid = p.id
  left join history_events ph on ph.postid = p.id
  left join tag_stats ts on ts.post_id = p.id
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '730 days'
),
user_quality as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.location,
    e.q_count,
    e.a_count,
    e.avg_q_score_nonzero,
    e.avg_a_score_nonzero,
    e.median_score,
    e.total_views,
    e.total_post_comments,
    e.total_favorites,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.post_active_days,
    r.comment_active_days,
    coalesce(sum(h.hotness_score) filter (where p.posttypeid = 1), 0) as sum_hotness_questions,
    coalesce(avg(h.hotness_score) filter (where p.posttypeid = 1), 0) as avg_hotness_questions,
    count(*) filter (where p.posttypeid = 1 and h.hotness_score > 5) as hot_questions_gt5,
    sum(case when q.id is not null then 1 else 0 end) as accepted_answers_given
  from recent_active_users r
  left join posts p on p.owneruserid = r.user_id
                    and p.creationdate >= now() - interval '730 days'
                    and p.posttypeid in (1,2)
  left join hotness h on h.post_id = p.id and p.posttypeid = 1
  left join accepted_map am on am.accepted_owner_id = r.user_id
  left join posts q on q.id = am.question_id
  left join engagement e on e.user_id = r.user_id
  group by r.user_id, r.displayname, r.reputation, r.location,
           e.q_count, e.a_count, e.avg_q_score_nonzero, e.avg_a_score_nonzero,
           e.median_score, e.total_views, e.total_post_comments, e.total_favorites,
           r.gold_badges, r.silver_badges, r.bronze_badges, r.post_active_days, r.comment_active_days
),
ranked_users as (
  select
    uq.*,
    dense_rank() over (order by
      coalesce(uq.avg_hotness_questions,0) desc,
      coalesce(uq.a_count,0) desc,
      coalesce(uq.q_count,0) desc,
      coalesce(uq.reputation,0) desc
    ) as overall_rank
  from user_quality uq
),
top_questions as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    p.title,
    p.score,
    p.viewcount,
    p.creationdate,
    h.hotness_score,
    row_number() over (partition by p.owneruserid order by h.hotness_score desc, p.score desc, p.viewcount desc) as rn
  from posts p
  join hotness h on h.post_id = p.id
)
select
  ru.overall_rank,
  ru.user_id,
  ru.displayname,
  ru.reputation,
  ru.location,
  ru.gold_badges,
  ru.silver_badges,
  ru.bronze_badges,
  ru.q_count,
  ru.a_count,
  ru.avg_q_score_nonzero,
  ru.avg_a_score_nonzero,
  ru.median_score,
  ru.total_views,
  ru.total_post_comments,
  ru.total_favorites,
  ru.post_active_days,
  ru.comment_active_days,
  ru.sum_hotness_questions,
  ru.avg_hotness_questions,
  ru.hot_questions_gt5,
  tq.post_id as top_question_id,
  tq.title as top_question_title,
  tq.score as top_question_score,
  tq.viewcount as top_question_views,
  tq.creationdate as top_question_created,
  tq.hotness_score as top_question_hotness
from ranked_users ru
left join top_questions tq
  on tq.user_id = ru.user_id
 and tq.rn = 1
where ru.overall_rank <= 200
order by ru.overall_rank, ru.user_id;