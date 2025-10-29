-- {"query": "195.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3621}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
         date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
badge_ranks as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_count,
         count(*) filter (where b.class = 2) as silver_count,
         count(*) filter (where b.class = 3) as bronze_count,
         count(*) as total_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_fact as (
  select p.id as post_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.commentcount,
         p.favoritecount,
         p.answercount,
         p.closeddate,
         p.communityowneddate,
         p.title,
         p.tags,
         coalesce(p.viewcount, 0) / nullif(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - p.creationdate)) / 86400.0, 1), 0) as views_per_day,
         case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
accepted_answers as (
  select a.id as answer_id,
         q.id as question_id,
         a.owneruserid as answerer_id,
         q.owneruserid as asker_id,
         a.score as answer_score,
         a.creationdate as answer_date,
         q.acceptedanswerid
  from posts q
  join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
  where q.posttypeid = 1
),
user_vote_summaries as (
  select v.userid,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) filter (where v.votetypeid = 5) as favorites_cast,
         count(*) filter (where v.votetypeid = 8) as bounties_started,
         sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from votes v
  group by v.userid
),
post_vote_summaries as (
  select v.postid,
         count(*) filter (where v.votetypeid = 2) as upvotes_rcv,
         count(*) filter (where v.votetypeid = 3) as downvotes_rcv,
         count(*) filter (where v.votetypeid = 8) as bounties_started_on_post,
         count(*) filter (where v.votetypeid = 9) as bounties_closed_on_post,
         sum(v.bountyamount) filter (where v.votetypeid = 9) as bounty_awarded_on_post
  from votes v
  group by v.postid
),
comment_agg as (
  select c.userid,
         count(*) as comments_made,
         coalesce(sum(c.score), 0) as comment_score_sum,
         avg(c.score) as comment_score_avg,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.userid
),
tag_extract as (
  select q.post_id,
         unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
  from question_fact q
  where q.tags is not null and q.tags like '<%>'
),
user_top_tag as (
  select q.user_id,
         t.tag,
         count(*) as tag_use_count,
         row_number() over (partition by q.user_id order by count(*) desc, min(q.creationdate)) as rn
  from question_fact q
  join tag_extract t on t.post_id = q.post_id
  group by q.user_id, t.tag
),
linkage as (
  select pl.postid as post_id,
         count(*) filter (where pl.linktypeid = 1) as links_linked,
         count(*) filter (where pl.linktypeid = 3) as links_duplicate
  from postlinks pl
  group by pl.postid
),
closed_reasons as (
  select ph.postid,
         min(ph.creationdate) as first_close_date,
         min(case when ph.posthistorytypeid = 10 then
                    case when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer) else null end
              end) as close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
question_enriched as (
  select q.*,
         pvs.upvotes_rcv,
         pvs.downvotes_rcv,
         pvs.bounties_started_on_post,
         pvs.bounties_closed_on_post,
         pvs.bounty_awarded_on_post,
         l.links_linked,
         l.links_duplicate,
         cr.first_close_date,
         cr.close_reason_id
  from question_fact q
  left join post_vote_summaries pvs on pvs.postid = q.post_id
  left join linkage l on l.post_id = q.post_id
  left join closed_reasons cr on cr.postid = q.post_id
),
user_rollup as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.cohort_month,
         ru.location,
         ru.websiteurl_norm,
         br.gold_count,
         br.silver_count,
         br.bronze_count,
         br.total_badges,
         br.last_badge_date,
         uvs.upvotes_cast,
         uvs.downvotes_cast,
         uvs.favorites_cast,
         uvs.bounties_started,
         uvs.bounty_amount_total,
         ca.comments_made,
         ca.comment_score_sum,
         ca.comment_score_avg,
         ca.last_comment_date
  from recent_users ru
  left join badge_ranks br on br.userid = ru.user_id
  left join user_vote_summaries uvs on uvs.userid = ru.user_id
  left join comment_agg ca on ca.userid = ru.user_id
),
question_stats as (
  select
    qe.user_id,
    count(*) as q_count,
    sum(qe.is_closed) as q_closed_count,
    avg(qe.score) as q_avg_score,
    sum(qe.viewcount) as q_total_views,
    avg(qe.views_per_day) as q_avg_views_per_day,
    sum(coalesce(qe.upvotes_rcv,0)) as q_upvotes_rcv,
    sum(coalesce(qe.downvotes_rcv,0)) as q_downvotes_rcv,
    sum(coalesce(qe.bounty_awarded_on_post,0)) as q_bounty_awarded_total,
    count(*) filter (where qe.answercount > 0) as q_with_answers,
    count(*) filter (where qe.links_duplicate > 0) as q_marked_duplicate,
    count(*) filter (where qe.tags ilike '%<sql>%') as q_sql_tagged,
    min(qe.creationdate) as first_q_date,
    max(qe.creationdate) as last_q_date
  from question_enriched qe
  group by qe.user_id
),
answer_stats as (
  select a.owneruserid as user_id,
         count(*) as a_count,
         count(*) filter (where exists (
             select 1
             from posts q2
             where q2.id = a.parentid and q2.acceptedanswerid = a.id
         )) as a_accepted_count,
         avg(a.score) as a_avg_score,
         sum(coalesce(pvs.upvotes_rcv,0)) as a_upvotes_rcv,
         sum(coalesce(pvs.downvotes_rcv,0)) as a_downvotes_rcv,
         min(a.creationdate) as first_a_date,
         max(a.creationdate) as last_a_date
  from posts a
  left join post_vote_summaries pvs on pvs.postid = a.id
  where a.posttypeid = 2
    and a.owneruserid is not null
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by a.owneruserid
),
accept_cross as (
  select aa.asker_id as user_id,
         count(*) as accepts_received_as_asker
  from accepted_answers aa
  where aa.answer_date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by aa.asker_id
),
activity_windows as (
  select u.id as user_id,
         count(*) filter (where p.posttypeid in (1,2) and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as posts_30d,
         count(*) filter (where p.posttypeid in (1,2) and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as posts_90d,
         count(*) filter (where p.posttypeid in (1,2) and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') as posts_365d,
         sum(p.score) filter (where p.posttypeid in (1,2) and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') as score_365d
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
user_top_tag_pick as (
  select utt.user_id,
         utt.tag as top_tag
  from user_top_tag utt
  where utt.rn = 1
),
score_percentiles as (
  select q.user_id,
         percentile_cont(0.5) within group (order by q.score) as q_score_p50,
         percentile_cont(0.9) within group (order by q.score) as q_score_p90
  from question_enriched q
  group by q.user_id
),
null_guard as (
  select ur.*,
         coalesce(qs.q_count, 0) as q_count,
         coalesce(qs.q_closed_count, 0) as q_closed_count,
         qs.q_avg_score,
         coalesce(qs.q_total_views, 0) as q_total_views,
         qs.q_avg_views_per_day,
         coalesce(qs.q_upvotes_rcv, 0) as q_upvotes_rcv,
         coalesce(qs.q_downvotes_rcv, 0) as q_downvotes_rcv,
         coalesce(qs.q_bounty_awarded_total, 0) as q_bounty_awarded_total,
         coalesce(qs.q_with_answers, 0) as q_with_answers,
         coalesce(qs.q_marked_duplicate, 0) as q_marked_duplicate,
         qs.first_q_date,
         qs.last_q_date,
         coalesce(as2.a_count, 0) as a_count,
         coalesce(as2.a_accepted_count, 0) as a_accepted_count,
         as2.a_avg_score,
         coalesce(as2.a_upvotes_rcv, 0) as a_upvotes_rcv,
         coalesce(as2.a_downvotes_rcv, 0) as a_downvotes_rcv,
         as2.first_a_date,
         as2.last_a_date,
         coalesce(ac.accepts_received_as_asker, 0) as accepts_received_as_asker,
         coalesce(aw.posts_30d, 0) as posts_30d,
         coalesce(aw.posts_90d, 0) as posts_90d,
         coalesce(aw.posts_365d, 0) as posts_365d,
         coalesce(aw.score_365d, 0) as score_365d,
         utt.top_tag,
         sp.q_score_p50,
         sp.q_score_p90
  from user_rollup ur
  left join question_stats qs on qs.user_id = ur.user_id
  left join answer_stats as2 on as2.user_id = ur.user_id
  left join accept_cross ac on ac.user_id = ur.user_id
  left join activity_windows aw on aw.user_id = ur.user_id
  left join user_top_tag_pick utt on utt.user_id = ur.user_id
  left join score_percentiles sp on sp.user_id = ur.user_id
),
ranked as (
  select ng.*,
         (coalesce(ng.q_upvotes_rcv,0) + coalesce(ng.a_upvotes_rcv,0)
          - 2*(coalesce(ng.q_downvotes_rcv,0) + coalesce(ng.a_downvotes_rcv,0))) as net_votes_received,
         case
           when coalesce(ng.q_count,0) = 0 then null
           else cast(ng.q_with_answers as decimal) / nullif(ng.q_count,0)
         end as q_answer_rate,
         row_number() over (partition by ng.cohort_month order by coalesce(ng.reputation,0) desc, coalesce(ng.total_badges,0) desc) as rep_rank_in_cohort,
         dense_rank() over (order by coalesce(ng.q_total_views,0) + coalesce(ng.a_upvotes_rcv,0) desc) as visibility_rank_global
  from null_guard ng
),
finalized as (
  select r.*,
         case
           when r.top_tag is null then 'none'
           when lower(r.top_tag) = any (array['sql','postgresql','tsql','mysql','sqlite']) then 'db-focused'
           else 'generalist'
         end as tag_profile,
         case
           when r.comments_made is null then 'no-comments'
           when r.comment_score_avg >= 1 then 'positive'
           when r.comment_score_avg <= -0.5 then 'controversial'
           else 'neutral'
         end as comment_mood
  from ranked r
)
select
  f.user_id,
  f.displayname,
  f.reputation,
  f.cohort_month,
  f.location,
  f.websiteurl_norm,
  f.gold_count,
  f.silver_count,
  f.bronze_count,
  f.total_badges,
  f.last_badge_date,
  f.q_count,
  f.q_closed_count,
  round(coalesce(f.q_avg_score,0), 2) as q_avg_score,
  f.q_total_views,
  round(coalesce(f.q_avg_views_per_day,0), 3) as q_avg_views_per_day,
  f.q_upvotes_rcv,
  f.q_downvotes_rcv,
  f.q_bounty_awarded_total,
  f.q_with_answers,
  f.q_marked_duplicate,
  f.first_q_date,
  f.last_q_date,
  f.a_count,
  f.a_accepted_count,
  round(coalesce(f.a_avg_score,0), 2) as a_avg_score,
  f.a_upvotes_rcv,
  f.a_downvotes_rcv,
  f.first_a_date,
  f.last_a_date,
  f.accepts_received_as_asker,
  f.upvotes_cast,
  f.downvotes_cast,
  f.favorites_cast,
  f.bounties_started,
  f.bounty_amount_total,
  f.comments_made,
  f.comment_score_sum,
  round(coalesce(f.comment_score_avg,0), 2) as comment_score_avg,
  f.last_comment_date,
  f.posts_30d,
  f.posts_90d,
  f.posts_365d,
  f.score_365d,
  f.top_tag,
  f.q_score_p50,
  f.q_score_p90,
  f.net_votes_received,
  round(coalesce(f.q_answer_rate,0), 3) as q_answer_rate,
  f.rep_rank_in_cohort,
  f.visibility_rank_global,
  f.tag_profile,
  f.comment_mood
from finalized f
where
  (
    f.reputation >= 1000
    or (coalesce(f.q_count,0) + coalesce(f.a_count,0)) >= 50
    or coalesce(f.total_badges,0) >= 10
  )
  and not (
    lower(coalesce(f.location, '')) like '%test%'
    or lower(coalesce(f.location, '')) like '%unknown%'
  )
  and (
    f.top_tag is null
    or length(f.top_tag) between 2 and 35
  )
  and (
    f.last_q_date is not null
    or f.last_a_date is not null
    or f.last_comment_date is not null
  )
order by
  f.rep_rank_in_cohort,
  f.visibility_rank_global,
  f.user_id
limit 500;