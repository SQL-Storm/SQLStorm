-- {"query": "31.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3245} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
         row_number() over (order by u.creationdate desc, u.id desc) as rn_newest,
         ntile(10) over (order by u.reputation desc nulls last) as rep_decile
  from users u
),
badge_rollup as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_posts as (
  select p.owneruserid as user_id,
         count(*) filter (where p.posttypeid = 1) as q_count,
         count(*) filter (where p.posttypeid = 2) as a_count,
         avg(nullif(p.score, 0)) as avg_nonzero_score,
         sum(greatest(p.viewcount, 0)) as total_views,
         max(p.creationdate) as last_post_date
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
accepted_answers as (
  select a.owneruserid as user_id,
         count(*) as accepted_count
  from posts q
  join posts a
    on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and a.posttypeid = 2
    and a.owneruserid is not null
  group by a.owneruserid
),
comment_stats as (
  select c.userid as user_id,
         count(*) as comment_count,
         avg(c.score) as avg_comment_score,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
vote_stats as (
  select v.userid as user_id,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) filter (where v.votetypeid = 5) as favorites_cast,
         sum(coalesce(v.bountyamount,0)) as bounty_total_cast
  from votes v
  where v.userid is not null
  group by v.userid
),
post_reactions as (
  select p.owneruserid as user_id,
         count(*) filter (where v.votetypeid = 2) as upvotes_received,
         count(*) filter (where v.votetypeid = 3) as downvotes_received,
         count(*) filter (where v.votetypeid = 1) as accepts_received
  from posts p
  left join votes v
    on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
question_tag_counts as (
  select p.owneruserid as user_id,
         sum(cardinality(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))) as tag_token_count,
         count(*) as tagged_question_count
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
    and p.tags is not null
  group by p.owneruserid
),
closed_questions as (
  select p.owneruserid as user_id,
         count(*) as closed_q_count,
         min(p.closeddate) as first_closed_q_date
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
    and p.closeddate is not null
  group by p.owneruserid
),
duplicate_links as (
  select p.owneruserid as user_id,
         count(*) as dup_out_links
  from postlinks pl
  join posts p on p.id = pl.postid
  where pl.linktypeid = 3
    and p.owneruserid is not null
  group by p.owneruserid
),
edit_events as (
  select ph.userid as user_id,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events_count,
         count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_events_count,
         max(ph.creationdate) as last_ph_date
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
activity_span as (
  select u.id as user_id,
         (select min(p.creationdate) from posts p where p.owneruserid = u.id) as first_post_date,
         (select max(p.creationdate) from posts p where p.owneruserid = u.id) as last_post_date,
         (select min(c.creationdate) from comments c where c.userid = u.id) as first_comment_date,
         (select max(c.creationdate) from comments c where c.userid = u.id) as last_comment_date
  from users u
),
user_quality as (
  select u.id as user_id,
         case
           when coalesce(up.upvotes_received,0) + coalesce(up.downvotes_received,0) = 0 then null
           else round(100.0 * coalesce(up.upvotes_received,0)::numeric / nullif(coalesce(up.upvotes_received,0) + coalesce(up.downvotes_received,0),0), 2)
         end as upvote_ratio_pct,
         coalesce(aa.accepted_count,0) as accepted_answers,
         coalesce(uc.a_count,0) as answers_authored,
         case
           when coalesce(uc.a_count,0) = 0 then null
           else round(coalesce(aa.accepted_count,0)::numeric / nullif(uc.a_count,0), 4)
         end as accept_rate
  from users u
  left join post_reactions up on up.user_id = u.id
  left join accepted_answers aa on aa.user_id = u.id
  left join user_posts uc on uc.user_id = u.id
),
ranks as (
  select u.id as user_id,
         dense_rank() over (order by coalesce(pr.upvotes_received,0) - coalesce(pr.downvotes_received,0) desc, u.reputation desc, u.id) as net_vote_rank,
         dense_rank() over (order by coalesce(aa.accepted_count,0) desc, coalesce(uc.a_count,0) desc) as accepted_rank,
         percent_rank() over (order by coalesce(uc.total_views,0) desc) as views_pct_rank
  from users u
  left join post_reactions pr on pr.user_id = u.id
  left join accepted_answers aa on aa.user_id = u.id
  left join user_posts uc on uc.user_id = u.id
),
heavy_users as (
  select ru.user_id
  from recent_users ru
  left join user_posts up on up.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  where coalesce(up.q_count,0) + coalesce(up.a_count,0) + coalesce(cs.comment_count,0) >= 50
),
final_agg as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl,
    ru.rn_newest,
    ru.rep_decile,
    coalesce(br.total_badges,0) as total_badges,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    br.first_badge_date,
    br.last_badge_date,
    coalesce(up.q_count,0) as q_count,
    coalesce(up.a_count,0) as a_count,
    up.avg_nonzero_score,
    coalesce(up.total_views,0) as total_views,
    up.last_post_date,
    coalesce(aa.accepted_count,0) as accepted_count,
    coalesce(cs.comment_count,0) as comment_count,
    cs.avg_comment_score,
    cs.last_comment_date,
    coalesce(vs.upvotes_cast,0) as upvotes_cast,
    coalesce(vs.downvotes_cast,0) as downvotes_cast,
    coalesce(vs.favorites_cast,0) as favorites_cast,
    coalesce(vs.bounty_total_cast,0) as bounty_total_cast,
    coalesce(pr.upvotes_received,0) as upvotes_received,
    coalesce(pr.downvotes_received,0) as downvotes_received,
    coalesce(pr.accepts_received,0) as accepts_received,
    coalesce(qt.tag_token_count,0) as tag_token_count,
    coalesce(qt.tagged_question_count,0) as tagged_question_count,
    coalesce(cq.closed_q_count,0) as closed_q_count,
    cq.first_closed_q_date,
    coalesce(dl.dup_out_links,0) as dup_out_links,
    coalesce(ee.edit_events_count,0) as edit_events_count,
    coalesce(ee.mod_events_count,0) as mod_events_count,
    ee.last_ph_date,
    aq.upvote_ratio_pct,
    aq.accepted_answers,
    aq.answers_authored,
    aq.accept_rate,
    r.net_vote_rank,
    r.accepted_rank,
    r.views_pct_rank,
    case
      when hu.user_id is not null then true
      else false
    end as is_heavy_user
  from recent_users ru
  left join badge_rollup br on br.userid = ru.user_id
  left join user_posts up on up.user_id = ru.user_id
  left join accepted_answers aa on aa.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join vote_stats vs on vs.user_id = ru.user_id
  left join post_reactions pr on pr.user_id = ru.user_id
  left join question_tag_counts qt on qt.user_id = ru.user_id
  left join closed_questions cq on cq.user_id = ru.user_id
  left join duplicate_links dl on dl.user_id = ru.user_id
  left join edit_events ee on ee.user_id = ru.user_id
  left join user_quality aq on aq.user_id = ru.user_id
  left join ranks r on r.user_id = ru.user_id
  left join heavy_users hu on hu.user_id = ru.user_id
),
top_and_bottom as (
  select * from final_agg
  qualify
    row_number() over (order by reputation desc nulls last, total_views desc, total_badges desc, user_id) <= 50
    or row_number() over (order by reputation asc nulls last, total_views asc, total_badges asc, user_id) <= 50
),
tag_mix as (
  select p.owneruserid as user_id,
         count(*) filter (where lower(p.tags) like '%<python>%') as py_qs,
         count(*) filter (where lower(p.tags) like '%<java>%') as java_qs,
         count(*) filter (where lower(p.tags) like '%<javascript>%') as js_qs
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
  group by p.owneruserid
)
select
  fa.user_id,
  coalesce(nullif(fa.displayname, ''), concat('user-', fa.user_id::varchar)) as displayname,
  fa.reputation,
  fa.rep_decile,
  fa.rn_newest,
  fa.total_badges,
  fa.gold_badges,
  fa.silver_badges,
  fa.bronze_badges,
  fa.q_count,
  fa.a_count,
  fa.accepted_count,
  fa.upvotes_received,
  fa.downvotes_received,
  fa.accepts_received,
  fa.upvotes_cast,
  fa.downvotes_cast,
  fa.favorites_cast,
  fa.total_views,
  fa.closed_q_count,
  fa.dup_out_links,
  fa.edit_events_count,
  fa.mod_events_count,
  round(coalesce(fa.avg_nonzero_score, 0)::numeric, 3) as avg_nonzero_score,
  round(coalesce(fa.views_pct_rank, 0)::numeric, 4) as views_pct_rank,
  coalesce(fa.upvote_ratio_pct, 0) as upvote_ratio_pct,
  coalesce(fa.accept_rate, 0) as accept_rate,
  case
    when (coalesce(fa.upvotes_received,0) - coalesce(fa.downvotes_received,0)) > 1000 then 'superb'
    when (coalesce(fa.upvotes_received,0) - coalesce(fa.downvotes_received,0)) between 100 and 1000 then 'great'
    when (coalesce(fa.upvotes_received,0) - coalesce(fa.downvotes_received,0)) between 10 and 99 then 'good'
    when (coalesce(fa.upvotes_received,0) - coalesce(fa.downvotes_received,0)) between -9 and 9 then 'neutral'
    else 'controversial'
  end as sentiment_bucket,
  tm.py_qs,
  tm.java_qs,
  tm.js_qs,
  case
    when tm.py_qs > greatest(tm.java_qs, tm.js_qs) then 'python-heavy'
    when tm.java_qs > greatest(tm.py_qs, tm.js_qs) then 'java-heavy'
    when tm.js_qs > greatest(tm.py_qs, tm.java_qs) then 'javascript-heavy'
    else 'mixed/other'
  end as tag_focus,
  fa.is_heavy_user,
  fa.net_vote_rank,
  fa.accepted_rank,
  coalesce(to_char(fa.creationdate, 'YYYY-MM'), 'unknown') as created_month,
  coalesce(nullif(trim(fa.location), ''), 'unspecified') as location_norm
from final_agg fa
left join tag_mix tm on tm.user_id = fa.user_id
where
  (
    fa.is_heavy_user
    or coalesce(fa.gold_badges,0) >= 1
    or (fa.reputation >= 10000 and coalesce(fa.accept_rate,0) >= 0.2)
    or (fa.views_pct_rank >= 0.99 and fa.total_views > 0)
  )
  and (
    fa.last_post_date is null
    or fa.last_post_date >= fa.creationdate
  )
  and not (
    fa.location ilike any (array['%bot%', '%test%', '%dummy%'])
    and fa.reputation < 100
  )
order by
  fa.net_vote_rank,
  fa.accepted_rank,
  fa.user_id
limit 500;