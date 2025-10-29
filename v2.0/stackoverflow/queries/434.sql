-- {"query": "434.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3395}
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
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
         count(case when p.posttypeid = 1 then 1 end) as questions,
         count(case when p.posttypeid = 2 then 1 end) as answers,
         count(*) as total_posts,
         sum(coalesce(p.score,0)) as total_score,
         sum(coalesce(p.viewcount,0)) as total_views,
         max(p.lastactivitydate) as last_post_activity,
         sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
q_detail as (
  select p.owneruserid as user_id,
         count(distinct p.id) as q_count,
         sum(coalesce(p.answercount,0)) as q_answercount_sum,
         avg(nullif(p.favoritecount,0)) as avg_favorites_nonzero,
         sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_qs,
         count(case when p.tags is not null then 1 end) as tagged_qs,
         sum(length(coalesce(p.title,''))) as sum_title_len
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
a_detail as (
  select p.owneruserid as user_id,
         count(distinct p.id) as a_count,
         sum(case when p.score > 0 then 1 else 0 end) as positive_answers,
         sum(case when p.score < 0 then 1 else 0 end) as negative_answers,
         sum(case when p.score = 0 then 1 else 0 end) as neutral_answers
  from posts p
  where p.posttypeid = 2
  group by p.owneruserid
),
comment_stats as (
  select c.userid as user_id,
         count(*) as comments,
         coalesce(sum(c.score),0) as comment_score,
         avg(case when c.score is not null then cast(c.score as numeric) end) as avg_comment_score,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.userid
),
vote_stats as (
  select v.userid as user_id,
         count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
         count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
         count(case when v.votetypeid = 5 then 1 end) as favorites_cast,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_cast,
         min(v.creationdate) as first_vote_date,
         max(v.creationdate) as last_vote_date
  from votes v
  group by v.userid
),
post_interactions as (
  select p.owneruserid as user_id,
         sum(v2_up.cnt) as received_upvotes,
         sum(v2_dn.cnt) as received_downvotes,
         sum(v2_fav.cnt) as received_favorites,
         sum(v2_bounty_amt.amt) as received_bounty
  from posts p
  left join lateral (
    select count(*) as cnt from votes v where v.postid = p.id and v.votetypeid = 2
  ) v2_up on true
  left join lateral (
    select count(*) as cnt from votes v where v.postid = p.id and v.votetypeid = 3
  ) v2_dn on true
  left join lateral (
    select count(*) as cnt from votes v where v.postid = p.id and v.votetypeid = 5
  ) v2_fav on true
  left join lateral (
    select coalesce(sum(v.bountyamount),0) as amt from votes v where v.postid = p.id and v.votetypeid in (8,9)
  ) v2_bounty_amt on true
  where p.owneruserid is not null
  group by p.owneruserid
),
closure_events as (
  select ph.postid,
         ph.userid as voter_user_id,
         max(ph.creationdate) as last_close_event,
         max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
         max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
         max(case when ph.posthistorytypeid in (10,11) then cast(nullif(ph.comment,'') as integer) end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid, ph.userid
),
closure_enriched as (
  select ce.voter_user_id as user_id,
         count(case when ce.was_closed = 1 then 1 end) as close_votes_made,
         count(case when ce.was_reopened = 1 then 1 end) as reopen_votes_made,
         count(case when ce.was_closed = 1 and ce.last_close_reason_id in (101,1) then 1 end) as duplicate_votes_made
  from closure_events ce
  group by ce.voter_user_id
),
dup_links as (
  select pl.postid, count(*) as dup_links_out
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
user_activity_window as (
  select u.id as user_id,
         u.creationdate,
         lead(u.creationdate) over (order by u.creationdate) as next_user_creation,
         lag(u.creationdate) over (order by u.creationdate) as prev_user_creation,
         rank() over (order by u.reputation desc, u.id) as rep_rank_desc,
         dense_rank() over (order by date_trunc('month', u.creationdate)) as cohort_rank
  from users u
),
tag_usage as (
  select p.owneruserid as user_id,
         unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tags as (
  select tu.user_id,
         t.tagname,
         count(*) as uses,
         row_number() over (partition by tu.user_id order by count(*) desc, t.tagname) as rn
  from tag_usage tu
  join tags t on lower(t.tagname) = lower(tu.tagname)
  group by tu.user_id, t.tagname
),
user_top3_tags as (
  select user_id,
         string_agg(tagname || ':' || cast(uses as text), ', ' order by rn) as top3_tags
  from top_tags
  where rn <= 3
  group by user_id
),
activity_score as (
  select ru.user_id,
         (
           coalesce(up.total_posts,0) * 1.0
           + coalesce(up.total_score,0) * 2.5
           + coalesce(cs.comments,0) * 0.5
           + coalesce(vs.upvotes_cast,0) * 0.25
           - coalesce(vs.downvotes_cast,0) * 0.5
           + coalesce(pi.received_upvotes,0) * 0.75
           - coalesce(pi.received_downvotes,0) * 0.75
           + coalesce(qd.accepted_qs,0) * 3
           + coalesce(ad.positive_answers,0) * 1.5
           - coalesce(ad.negative_answers,0) * 1.5
         ) as raw_activity_score
  from recent_users ru
  left join user_posts up on up.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join vote_stats vs on vs.user_id = ru.user_id
  left join post_interactions pi on pi.user_id = ru.user_id
  left join q_detail qd on qd.user_id = ru.user_id
  left join a_detail ad on ad.user_id = ru.user_id
),
normalized as (
  select a.user_id,
         a.raw_activity_score,
         ntile(100) over (order by a.raw_activity_score nulls first) as percentile_bucket,
         avg(a.raw_activity_score) over () as avg_activity_score,
         stddev_pop(a.raw_activity_score) over () as stddev_activity_score
  from activity_score a
),
final_scores as (
  select n.user_id,
         n.raw_activity_score,
         n.percentile_bucket,
         case
           when n.stddev_activity_score is null or n.stddev_activity_score = 0 then null
           else (n.raw_activity_score - n.avg_activity_score) / n.stddev_activity_score
         end as zscore
  from normalized n
),
user_summary as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location,
         ru.websiteurl_norm,
         coalesce(br.total_badges,0) as total_badges,
         coalesce(br.gold_badges,0) as gold_badges,
         coalesce(br.silver_badges,0) as silver_badges,
         coalesce(br.bronze_badges,0) as bronze_badges,
         up.total_posts,
         up.questions,
         up.answers,
         up.total_score,
         up.total_views,
         up.closed_posts,
         qd.q_count,
         qd.q_answercount_sum,
         qd.avg_favorites_nonzero,
         ad.a_count,
         ad.positive_answers,
         ad.negative_answers,
         ad.neutral_answers,
         cs.comments,
         cs.comment_score,
         cs.last_comment_date,
         vs.upvotes_cast,
         vs.downvotes_cast,
         vs.favorites_cast,
         vs.bounty_total_cast,
         vs.first_vote_date,
         vs.last_vote_date,
         pi.received_upvotes,
         pi.received_downvotes,
         pi.received_favorites,
         pi.received_bounty,
         ce.close_votes_made,
         ce.reopen_votes_made,
         ce.duplicate_votes_made,
         fs.raw_activity_score,
         fs.percentile_bucket,
         fs.zscore,
         ut.top3_tags,
         uaw.rep_rank_desc,
         uaw.cohort_rank,
         uaw.prev_user_creation,
         uaw.next_user_creation
  from recent_users ru
  left join badge_rollup br on br.userid = ru.user_id
  left join user_posts up on up.user_id = ru.user_id
  left join q_detail qd on qd.user_id = ru.user_id
  left join a_detail ad on ad.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join vote_stats vs on vs.user_id = ru.user_id
  left join post_interactions pi on pi.user_id = ru.user_id
  left join closure_enriched ce on ce.user_id = ru.user_id
  left join final_scores fs on fs.user_id = ru.user_id
  left join user_top3_tags ut on ut.user_id = ru.user_id
  left join user_activity_window uaw on uaw.user_id = ru.user_id
),
ranked as (
  select us.*,
         row_number() over (order by coalesce(us.zscore, -1e9) desc, coalesce(us.raw_activity_score, -1e9) desc, us.reputation desc, us.user_id) as overall_rank,
         row_number() over (partition by coalesce(us.location,'Unknown') order by coalesce(us.zscore, -1e9) desc) as location_rank
  from user_summary us
)
select
  r.overall_rank,
  r.location_rank,
  r.user_id,
  r.displayname,
  r.location,
  r.reputation,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.total_posts,
  r.questions,
  r.answers,
  r.total_score,
  r.total_views,
  r.closed_posts,
  r.q_count,
  r.q_answercount_sum,
  coalesce(r.avg_favorites_nonzero, 0) as avg_favorites_nonzero,
  r.a_count,
  r.positive_answers,
  r.negative_answers,
  r.neutral_answers,
  r.comments,
  r.comment_score,
  r.received_upvotes,
  r.received_downvotes,
  r.received_favorites,
  r.received_bounty,
  r.close_votes_made,
  r.reopen_votes_made,
  r.duplicate_votes_made,
  r.percentile_bucket,
  coalesce(r.zscore, 0) as zscore,
  coalesce(r.top3_tags, 'none') as top3_tags,
  case when r.websiteurl_norm like 'http%' then r.websiteurl_norm else null end as websiteurl_http,
  case when r.total_posts is null or r.total_posts = 0 then null else (cast(r.total_score as numeric) / nullif(r.total_posts,0)) end as avg_score_per_post,
  case when r.answers is null or r.answers = 0 then 0 else (cast(r.positive_answers as numeric) / nullif(r.answers,0)) end as pct_positive_answers,
  case when r.q_count is null or r.q_count = 0 then 0 else (cast(r.q_answercount_sum as numeric) / nullif(r.q_count,0)) end as avg_answers_per_question,
  case when (coalesce(r.received_upvotes,0) + coalesce(r.received_downvotes,0)) = 0 or r.received_upvotes is null or r.received_downvotes is null
       then null
       else (cast(r.received_upvotes as numeric) / nullif((r.received_upvotes + r.received_downvotes),0)) end as upvote_ratio_received,
  r.creationdate as user_created_at,
  r.prev_user_creation,
  r.next_user_creation
from ranked r
where
  (
    r.reputation >= coalesce(
      (select percentile_disc(0.75) within group (order by reputation) from users), 0
    )
    or coalesce(r.zscore, -10) > 1.0
  )
  and (
    exists (
      select 1
      from posts p
      left join dup_links dl on dl.postid = p.id
      where p.owneruserid = r.user_id
        and (coalesce(dl.dup_links_out,0) > 0 or p.score > 10 or p.viewcount > 1000)
        and (
          p.lastactivitydate >= r.creationdate
          or p.lasteditdate is not null
        )
    )
    or exists (
      select 1
      from comments c
      where c.userid = r.user_id and c.score >= 5
    )
  )
order by r.overall_rank
limit 200;