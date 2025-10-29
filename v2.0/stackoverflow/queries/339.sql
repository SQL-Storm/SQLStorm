-- {"query": "339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2802}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''), '/', 3)), ''), 'unknown') as domain_host
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_rollup as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) as total_badges,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_post_activity as (
  select p.owneruserid as user_id,
         sum(case when p.posttypeid = 1 then 1 else 0 end) as questions,
         sum(case when p.posttypeid = 2 then 1 else 0 end) as answers,
         sum(coalesce(p.score,0)) as total_post_score,
         avg(nullif(p.viewcount,0)) as avg_viewcount_nonzero,
         max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
question_metrics as (
  select q.owneruserid as user_id,
         count(*) as total_questions,
         sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
         avg(q.answercount) as avg_answers_per_question,
         avg(coalesce(q.viewcount,0)) as p90_views_replacement,
         avg(coalesce(q.score,0)) as avg_q_score
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
answer_metrics as (
  select a.owneruserid as user_id,
         count(*) as total_answers,
         sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
         avg(coalesce(a.score,0)) as avg_a_score
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
comment_stats as (
  select c.userid as user_id,
         count(*) as comments_count,
         sum(coalesce(c.score,0)) as comment_score,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
duplicate_closures as (
  select ph.postid,
         min(ph.creationdate) as first_dup_close_date,
         count(*) as dup_close_events
  from posthistory ph
  where ph.posthistorytypeid in (10,35)
    and (cast(ph.comment as text) ~ '(^|[^0-9])101([^0-9]|$)' or ph.text like '%OriginalQuestionIds%')
  group by ph.postid
),
postlink_dups as (
  select pl.postid, count(*) as duplicate_links
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
question_enrichment as (
  select q.id as post_id,
         q.owneruserid as user_id,
         q.creationdate,
         q.score,
         q.viewcount,
         q.title,
         q.tags,
         coalesce(dc.dup_close_events,0) as dup_close_events,
         coalesce(pld.duplicate_links,0) as duplicate_links
  from posts q
  left join duplicate_closures dc on dc.postid = q.id
  left join postlink_dups pld on pld.postid = q.id
  where q.posttypeid = 1
),
user_windowed as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location,
         ru.domain_host,
         row_number() over (order by ru.reputation desc, ru.creationdate asc) as rn_global,
         dense_rank() over (partition by case when ru.location is null or trim(ru.location) = '' then 'unknown' else ru.location end
                            order by ru.reputation desc) as dr_loc_rep,
         avg(ru.reputation) over () as avg_rep_all,
         null::numeric as p75_rep_all
  from recent_users ru
  group by ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.domain_host
),
activity_agg as (
  select qe.user_id,
         count(*) as q_count,
         sum(case when qe.score >= 5 then 1 else 0 end) as hot_qs,
         sum(qe.dup_close_events) as total_dup_closures,
         sum(qe.duplicate_links) as total_dup_links,
         max(qe.viewcount) as max_q_views,
         min(qe.viewcount) filter (where qe.viewcount is not null and qe.viewcount > 0) as min_positive_views,
         count(*) filter (where qe.tags is null) as untagged_qs
  from question_enrichment qe
  group by qe.user_id
),
votes_rollup as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_sum
  from votes v
  group by v.postid
),
user_vote_impact as (
  select p.owneruserid as user_id,
         sum(coalesce(vr.upvotes,0)) as recv_upvotes,
         sum(coalesce(vr.downvotes,0)) as recv_downvotes,
         sum(coalesce(vr.favorites,0)) as recv_favorites,
         sum(coalesce(vr.bounty_sum,0)) as recv_bounty
  from posts p
  left join votes_rollup vr on vr.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
stringy as (
  select u.id as user_id,
         length(coalesce(u.aboutme,'')) as about_len,
         case
           when coalesce(u.displayname,'') ~ '^[A-Za-z0-9_.-]{3,}$' then 1 else 0
         end as simple_handle,
         coalesce(nullif(trim(u.location),''),'unknown') as norm_location,
         upper(substr(coalesce(u.displayname,''), 1, 1)) as name_initial
  from users u
),
cte_union as (
  select userid as user_id, date as activity_date, 'badge' as kind from badges
  union all
  select owneruserid, creationdate, 'post' from posts where owneruserid is not null
  union all
  select userid, creationdate, 'comment' from comments where userid is not null
),
user_recency as (
  select cu.user_id,
         max(cu.activity_date) as last_seen_any,
         count(*) filter (where cu.activity_date >= (timestamp '2024-10-01 12:34:56' - interval '30 days')) as last30_events
  from cte_union cu
  group by cu.user_id
),
flag_posttypes as (
  select pt.id as posttype_id, pt.name as posttype_name
  from posttypes pt
),
heavy_join as (
  select p.id as post_id,
         p.owneruserid as user_id,
         pt.posttype_name,
         coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0) as net_votes,
         coalesce(vr.favorites,0) as favs,
         coalesce(vr.bounty_sum,0) as bounty_sum,
         coalesce(pl.linktypeid,0) as any_linktype_id
  from posts p
  left join votes_rollup vr on vr.postid = p.id
  left join postlinks pl on pl.postid = p.id and pl.linktypeid in (1,3)
  left join flag_posttypes pt on pt.posttype_id = p.posttypeid
)
select
  uw.user_id,
  uw.displayname,
  uw.reputation,
  uw.location,
  uw.domain_host,
  uw.rn_global,
  uw.dr_loc_rep,
  br.gold_badges,
  br.silver_badges,
  br.bronze_badges,
  coalesce(br.total_badges,0) as total_badges,
  upa.questions,
  upa.answers,
  upa.total_post_score,
  qmet.total_questions,
  qmet.accepted_questions,
  qmet.avg_answers_per_question,
  qmet.p90_views_replacement as p90_views,
  amet.total_answers,
  amet.positive_answers,
  amet.avg_a_score,
  cs.comments_count,
  cs.comment_score,
  cs.last_comment_date,
  aa.q_count,
  aa.hot_qs,
  aa.total_dup_closures,
  aa.total_dup_links,
  aa.max_q_views,
  aa.min_positive_views,
  aa.untagged_qs,
  uvi.recv_upvotes,
  uvi.recv_downvotes,
  uvi.recv_favorites,
  uvi.recv_bounty,
  s.about_len,
  s.simple_handle,
  s.norm_location,
  s.name_initial,
  ur.last_seen_any,
  ur.last30_events,
  case when coalesce(upa.answers,0) > 0 and coalesce(upa.questions,0) > 0 then round(cast(upa.answers as numeric) / nullif(upa.questions,0), 3) else null end as answer_question_ratio,
  case when uw.reputation >= coalesce(uw.p75_rep_all, 0) then 'top_quartile' else 'other' end as rep_bucket,
  case when coalesce(qmet.total_questions,0) > 0 then round(cast(qmet.accepted_questions as numeric) / nullif(qmet.total_questions,0), 3) else null end as accept_rate,
  case when coalesce(cs.comment_score,0) < 0 then 1 else 0 end as has_controversial_comments,
  case when br.first_badge_date is null then 'newbie' when br.first_badge_date > (timestamp '2024-10-01 12:34:56' - interval '90 days') then 'recent_badger' else 'established' end as badge_age_class,
  rank() over (
    partition by case when uw.location is null or trim(uw.location) = '' then 'unknown' else uw.location end
    order by coalesce(uvi.recv_upvotes,0) + coalesce(upa.total_post_score,0) desc
  ) as loc_rank_by_impact,
  (
    select count(*) from posts p2
    where p2.owneruserid = uw.user_id
      and p2.posttypeid = 1
      and exists (
        select 1 from comments c2
        where c2.postid = p2.id
          and coalesce(c2.score,0) > 5
      )
  ) as questions_with_popular_comments,
  case when exists (
    select 1
    from heavy_join hj
    where hj.user_id = uw.user_id
      and (hj.net_votes > 10 or (hj.favs > 20 and hj.posttype_name is not null))
      and not (hj.posttype_name = 'Wiki' and hj.net_votes < 0)
  ) then 1 else 0 end as has_high_impact_post,
  (
    select avg(net_votes) from (
      select coalesce(vr2.upvotes,0) - coalesce(vr2.downvotes,0) as net_votes
      from votes_rollup vr2
    ) t
  ) as global_avg_net_votes
from user_windowed uw
left join badge_rollup br on br.userid = uw.user_id
left join user_post_activity upa on upa.user_id = uw.user_id
left join question_metrics qmet on qmet.user_id = uw.user_id
left join answer_metrics amet on amet.user_id = uw.user_id
left join comment_stats cs on cs.user_id = uw.user_id
left join activity_agg aa on aa.user_id = uw.user_id
left join user_vote_impact uvi on uvi.user_id = uw.user_id
left join stringy s on s.user_id = uw.user_id
left join user_recency ur on ur.user_id = uw.user_id
where coalesce(uw.displayname,'') <> ''
  and (coalesce(upa.questions,0) + coalesce(upa.answers,0)) >= 1
  and (
    br.total_badges is null
    or br.total_badges >= 0
  )
order by rep_bucket desc, loc_rank_by_impact nulls last, uw.reputation desc
limit 500;