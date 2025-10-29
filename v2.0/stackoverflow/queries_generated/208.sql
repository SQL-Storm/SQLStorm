-- {"query": "208.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2571} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
    u.upvotes,
    u.downvotes,
    u.views,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '3 years' from posts p)
),
user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    count(distinct p.id) as total_posts,
    coalesce(sum(case when p.posttypeid in (1,2) then p.score end), 0) as post_score_sum,
    coalesce(sum(p.viewcount), 0) as views_sum,
    max(p.lastactivitydate) as last_post_activity
  from recent_users u
  left join posts p
    on p.owneruserid = u.id
    and p.creationdate >= u.creationdate
  group by u.id
),
vote_agg as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_rcvd,
    count(*) filter (where v.votetypeid = 3) as downvotes_rcvd,
    count(*) filter (where v.votetypeid = 1) as accepts_rcvd,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    coalesce(sum(v.bountyamount) filter (where v.votetypeid in (8,9)), 0) as bounty_amount_sum
  from posts p
  join votes v
    on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_agg as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    coalesce(sum(c.score), 0) as comment_score_sum,
    max(c.creationdate) as last_comment_date,
    percentile_cont(0.5) within group (order by c.score) as comment_score_median
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_agg as (
  select
    b.userid as user_id,
    count(*) filter (where b.class = 1) as golds,
    count(*) filter (where b.class = 2) as silvers,
    count(*) filter (where b.class = 3) as bronzes,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) filter (where p.posttypeid = 1) as avg_q_score,
    avg(p.viewcount) filter (where p.posttypeid = 1) as avg_q_views,
    avg(p.answercount::numeric) as avg_answers_per_q,
    count(*) filter (where p.acceptedanswerid is not null) as accepted_q_count
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
answer_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) as avg_a_score,
    sum(case when p.score >= 1 then 1 else 0 end) as pos_a_count,
    sum(case when p.score <= -1 then 1 else 0 end) as neg_a_count
  from posts p
  where p.posttypeid = 2
  group by p.owneruserid
),
closure_events as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid = 10) as closes_made,
    count(*) filter (where ph.posthistorytypeid = 11) as reopens_made,
    count(*) filter (where ph.posthistorytypeid = 10 and try_cast(ph.comment as int) in (101,102,103,104,105)) as typed_closes_made
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
dup_links as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3) as dup_links_from_post,
    count(*) filter (where pl.linktypeid = 1) as linked_links_from_post
  from posts p
  left join postlinks pl
    on pl.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
tag_expertise as (
  select
    p.owneruserid as user_id,
    t.tagname,
    count(*) as tag_posts,
    avg(p.score) as tag_avg_score,
    row_number() over (partition by p.owneruserid order by count(*) desc, avg(p.score) desc, min(p.creationdate)) as tag_rank
  from posts p
  join lateral (
    select unnest(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')) as tagname
  ) ta on p.posttypeid = 1 and p.tags is not null
  join tags t on lower(t.tagname) = lower(ta.tagname)
  where p.owneruserid is not null
  group by p.owneruserid, t.tagname
),
top_tags as (
  select user_id,
         string_agg(tagname || ':' || coalesce(to_char(tag_avg_score, 'FM999999990.00'), '0'), ', ' order by tag_rank)
           filter (where tag_rank <= 3) as top3_tags
  from tag_expertise
  group by user_id
),
user_rank as (
  select
    u.id as user_id,
    dense_rank() over (order by ua.total_posts desc nulls last, coalesce(va.upvotes_rcvd,0) - coalesce(va.downvotes_rcvd,0) desc, u.reputation desc) as activity_rank,
    ntile(10) over (order by u.reputation desc) as rep_decile
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
  left join vote_agg va on va.user_id = u.id
)
select
  u.id,
  coalesce(nullif(u.displayname, ''), '(anonymous)') as displayname,
  u.reputation,
  u.creationdate,
  coalesce(nullif(u.location, ''), 'Unknown') as location,
  u.websiteurl_norm,
  u.upvotes as upvotes_cast,
  u.downvotes as downvotes_cast,
  u.views as profile_views,
  ua.total_posts,
  ua.q_count,
  ua.a_count,
  ua.post_score_sum,
  ua.views_sum as post_views_sum,
  ua.last_post_activity,
  coalesce(va.upvotes_rcvd, 0) as upvotes_received,
  coalesce(va.downvotes_rcvd, 0) as downvotes_received,
  coalesce(va.accepts_rcvd, 0) as accepts_received,
  coalesce(va.bounty_events, 0) as bounty_events,
  coalesce(va.bounty_amount_sum, 0) as bounty_amount_sum,
  coalesce(ca.comment_count, 0) as comment_count,
  coalesce(ca.comment_score_sum, 0) as comment_score_sum,
  ca.last_comment_date,
  ca.comment_score_median,
  coalesce(ba.golds, 0) as gold_badges,
  coalesce(ba.silvers, 0) as silver_badges,
  coalesce(ba.bronzes, 0) as bronze_badges,
  coalesce(ba.tag_badges, 0) as tag_badges,
  ba.first_badge_date,
  ba.last_badge_date,
  qq.avg_q_score,
  qq.avg_q_views,
  qq.avg_answers_per_q,
  qq.accepted_q_count,
  aq.avg_a_score,
  aq.pos_a_count,
  aq.neg_a_count,
  coalesce(ce.closes_made, 0) as closes_made,
  coalesce(ce.reopens_made, 0) as reopens_made,
  coalesce(ce.typed_closes_made, 0) as typed_closes_made,
  coalesce(dl.dup_links_from_post, 0) as dup_links_from_post,
  coalesce(dl.linked_links_from_post, 0) as linked_links_from_post,
  tt.top3_tags,
  ur.activity_rank,
  ur.rep_decile,
  case
    when ua.total_posts is null or ua.total_posts = 0 then 'New'
    when coalesce(va.upvotes_rcvd,0) - coalesce(va.downvotes_rcvd,0) >= 100 then 'Influencer'
    when coalesce(ba.golds,0) >= 5 then 'Veteran'
    when coalesce(qq.avg_q_score,0) >= 5 and coalesce(aq.avg_a_score,0) >= 3 then 'All-rounder'
    when coalesce(aq.avg_a_score,0) >= 4 then 'Answerer'
    when coalesce(qq.avg_q_score,0) >= 4 then 'Questioner'
    else 'Contributor'
  end as user_archetype,
  round(
    coalesce(ua.post_score_sum,0) * 0.5
    + (coalesce(va.upvotes_rcvd,0) - coalesce(va.downvotes_rcvd,0)) * 0.8
    + coalesce(va.accepts_rcvd,0) * 3
    + coalesce(ba.golds,0) * 5
    + coalesce(ba.silvers,0) * 2
    + coalesce(ba.bronzes,0) * 1
    + least(coalesce(ua.views_sum,0) / nullif(ua.total_posts,0), 1000) * 0.01
    + coalesce(qq.avg_answers_per_q,0) * 2
    + coalesce(aq.pos_a_count,0) * 0.2
    - coalesce(aq.neg_a_count,0) * 0.3
  , 2) as perf_score
from recent_users u
left join user_activity ua on ua.user_id = u.id
left join vote_agg va on va.user_id = u.id
left join comment_agg ca on ca.user_id = u.id
left join badge_agg ba on ba.user_id = u.id
left join question_quality qq on qq.user_id = u.id
left join answer_quality aq on aq.user_id = u.id
left join closure_events ce on ce.user_id = u.id
left join dup_links dl on dl.user_id = u.id
left join top_tags tt on tt.user_id = u.id
left join user_rank ur on ur.user_id = u.id
where (
    u.rn <= 500
    or (ua.total_posts >= 50 and coalesce(va.upvotes_rcvd,0) - coalesce(va.downvotes_rcvd,0) >= 200)
  )
and (
    -- complex predicate to stress optimizer and NULL logic
    coalesce(qq.avg_q_score, -999) >= case when aq.avg_a_score is null then -999 else -1000 end
    and (u.location is null or position(' ' in coalesce(u.location,'')) > 0 or length(coalesce(u.location,'')) >= 3)
  )
order by perf_score desc nulls last, ur.activity_rank asc, u.id
limit 300;