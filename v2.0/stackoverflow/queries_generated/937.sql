-- {"query": "937.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3485} 
with params as (
  select
    date_trunc('month', now()) - interval '36 months' as start_month,
    date_trunc('month', now()) as end_month
),
months as (
  select generate_series(start_month, end_month, interval '1 month') as month_start
  from params
),
active_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         date_trunc('month', u.creationdate) as created_month,
         row_number() over (order by u.reputation desc, u.id) as rep_rank_global
  from users u
  where u.reputation > 0
),
posts_enriched as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.commentcount,
    case when p.closeddate is not null then 1 else 0 end as is_closed,
    date_trunc('month', p.creationdate) as month_bucket,
    (p.posttypeid = 1 and p.acceptedanswerid is not null)::int as q_with_accepted,
    (p.posttypeid = 2 and p.parentid is not null)::int as is_answer
  from posts p
  where p.creationdate >= (select start_month from params)
),
votes_agg as (
  select
    v.postid,
    date_trunc('month', v.creationdate) as v_month,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  where v.creationdate >= (select start_month from params)
  group by v.postid, date_trunc('month', v.creationdate)
),
comments_agg as (
  select
    c.postid,
    date_trunc('month', c.creationdate) as c_month,
    count(*) as comments_count,
    max(c.score) as max_comment_score
  from comments c
  where c.creationdate >= (select start_month from params)
  group by c.postid, date_trunc('month', c.creationdate)
),
postlinks_dupes as (
  select
    pl.postid,
    date_trunc('month', pl.creationdate) as l_month,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_links
  from postlinks pl
  where pl.creationdate >= (select start_month from params)
  group by pl.postid, date_trunc('month', pl.creationdate)
),
closings as (
  select
    ph.postid,
    date_trunc('month', ph.creationdate) as ph_month,
    count(*) filter (where ph.posthistorytypeid = 10) as closes,
    count(*) filter (where ph.posthistorytypeid = 11) as reopens,
    max(case when ph.posthistorytypeid = 10 then try_cast(nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') as int) end) as any_close_reason_id
  from posthistory ph
  where ph.creationdate >= (select start_month from params)
    and ph.posthistorytypeid in (10,11)
  group by ph.postid, date_trunc('month', ph.creationdate)
),
tag_expansion as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and p.creationdate >= (select start_month from params)
),
tag_quality as (
  select
    te.tagname,
    date_trunc('month', p.creationdate) as t_month,
    count(*) as q_count,
    avg(nullif(p.score,0)) as avg_score_nonzero,
    sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_qs
  from tag_expansion te
  join posts p on p.id = te.post_id
  group by te.tagname, date_trunc('month', p.creationdate)
),
user_month_activity as (
  select
    ae.user_id,
    m.month_start,
    sum(case when pe.posttypeid = 1 then 1 else 0 end) as questions,
    sum(case when pe.posttypeid = 2 then 1 else 0 end) as answers,
    sum(pe.q_with_accepted) as q_with_accepted,
    sum(pe.is_answer) as answers_flag,
    sum(coalesce(va.upvotes,0)) as upvotes,
    sum(coalesce(va.downvotes,0)) as downvotes,
    sum(coalesce(va.favorites,0)) as favorites,
    sum(coalesce(va.bounty_total,0)) as bounty_total,
    sum(coalesce(ca.comments_count,0)) as comments_count,
    max(coalesce(ca.max_comment_score,0)) as max_comment_score,
    sum(coalesce(pd.dup_links,0)) as dup_links,
    sum(coalesce(pd.linked_links,0)) as linked_links,
    sum(coalesce(cl.closes,0)) as closes,
    sum(coalesce(cl.reopens,0)) as reopens
  from months m
  left join posts_enriched pe
    on pe.month_bucket = m.month_start
  left join votes_agg va
    on va.postid = pe.id
    and va.v_month = m.month_start
  left join comments_agg ca
    on ca.postid = pe.id
    and ca.c_month = m.month_start
  left join postlinks_dupes pd
    on pd.postid = pe.id
    and pd.l_month = m.month_start
  left join closings cl
    on cl.postid = pe.id
    and cl.ph_month = m.month_start
  left join active_users ae
    on ae.user_id = pe.owneruserid
  group by ae.user_id, m.month_start
),
user_rollups as (
  select
    um.user_id,
    min(um.month_start) filter (where coalesce(um.questions,0)+coalesce(um.answers,0) > 0) as first_active_month,
    count(*) filter (where coalesce(um.questions,0)+coalesce(um.answers,0) > 0) as active_months,
    sum(coalesce(um.questions,0)) as total_questions,
    sum(coalesce(um.answers,0)) as total_answers,
    sum(coalesce(um.upvotes,0)) as total_upvotes,
    sum(coalesce(um.downvotes,0)) as total_downvotes,
    sum(coalesce(um.favorites,0)) as total_favorites,
    sum(coalesce(um.bounty_total,0)) as total_bounty,
    sum(coalesce(um.comments_count,0)) as total_comments,
    sum(coalesce(um.dup_links,0)) as total_dupe_links,
    sum(coalesce(um.closes,0)) as total_closes,
    sum(coalesce(um.reopens,0)) as total_reopens
  from user_month_activity um
  group by um.user_id
),
user_windowed as (
  select
    ar.user_id,
    au.displayname,
    au.location_norm,
    au.reputation,
    au.rep_rank_global,
    ar.first_active_month,
    ar.active_months,
    ar.total_questions,
    ar.total_answers,
    ar.total_upvotes,
    ar.total_downvotes,
    ar.total_favorites,
    ar.total_bounty,
    ar.total_comments,
    ar.total_dupe_links,
    ar.total_closes,
    ar.total_reopens,
    (ar.total_upvotes - ar.total_downvotes) as net_votes,
    (ar.total_answers + ar.total_questions) as total_posts,
    case when (ar.total_answers + ar.total_questions) = 0 then null
         else round( (ar.total_upvotes::numeric - ar.total_downvotes::numeric) / nullif(ar.total_answers + ar.total_questions,0), 4)
    end as net_votes_per_post,
    rank() over (order by (ar.total_upvotes - ar.total_downvotes) desc nulls last) as net_vote_rank,
    dense_rank() over (order by (ar.total_answers + ar.total_questions) desc nulls last) as volume_rank
  from user_rollups ar
  join active_users au on au.user_id = ar.user_id
),
badge_summaries as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
location_peers as (
  select
    uw.location_norm,
    percentile_cont(0.5) within group (order by uw.net_votes) as median_net_votes,
    avg(uw.total_posts) as avg_posts_loc,
    count(*) as users_in_loc
  from user_windowed uw
  where uw.location_norm is not null
  group by uw.location_norm
),
question_quality as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as q_month,
    count(*) as q_cnt,
    avg(p.score) as avg_q_score,
    sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_cnt
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select start_month from params)
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
answer_quality as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as a_month,
    count(*) as a_cnt,
    avg(p.score) as avg_a_score
  from posts p
  where p.posttypeid = 2
    and p.creationdate >= (select start_month from params)
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
monthly_user_quality as (
  select
    coalesce(q.user_id, a.user_id) as user_id,
    coalesce(q.q_month, a.a_month) as month_bucket,
    coalesce(q.q_cnt,0) as q_cnt,
    coalesce(a.a_cnt,0) as a_cnt,
    coalesce(q.avg_q_score,0) as avg_q_score,
    coalesce(a.avg_a_score,0) as avg_a_score,
    coalesce(q.accepted_cnt,0) as accepted_cnt
  from question_quality q
  full outer join answer_quality a
    on q.user_id = a.user_id
   and q.q_month = a.a_month
),
tag_top_per_month as (
  select
    tq.tagname,
    tq.t_month,
    tq.q_count,
    tq.avg_score_nonzero,
    row_number() over (partition by tq.t_month order by tq.q_count desc nulls last, tq.avg_score_nonzero desc nulls last, tq.tagname) as rn
  from tag_quality tq
),
final_users as (
  select
    uw.*,
    bs.gold_badges,
    bs.silver_badges,
    bs.bronze_badges,
    bs.tag_badges,
    lp.median_net_votes as loc_median_net_votes,
    lp.avg_posts_loc,
    lp.users_in_loc
  from user_windowed uw
  left join badge_summaries bs on bs.userid = uw.user_id
  left join location_peers lp on lp.location_norm = uw.location_norm
),
top_tags as (
  select
    tpm.t_month,
    tpm.tagname,
    tpm.q_count,
    tpm.avg_score_nonzero
  from tag_top_per_month tpm
  where tpm.rn <= 3
),
recent_activity as (
  select
    um.user_id,
    sum(um.questions) filter (where um.month_start >= (select end_month - interval '2 months' from params)) as last_3mo_qs,
    sum(um.answers) filter (where um.month_start >= (select end_month - interval '2 months' from params)) as last_3mo_as,
    sum(um.upvotes) filter (where um.month_start >= (select end_month - interval '2 months' from params)) as last_3mo_up,
    sum(um.downvotes) filter (where um.month_start >= (select end_month - interval '2 months' from params)) as last_3mo_down
  from user_month_activity um
  group by um.user_id
)
select
  fu.user_id,
  fu.displayname,
  fu.location_norm,
  fu.reputation,
  fu.rep_rank_global,
  fu.first_active_month,
  fu.active_months,
  fu.total_posts,
  fu.total_questions,
  fu.total_answers,
  fu.total_upvotes,
  fu.total_downvotes,
  fu.net_votes,
  fu.net_votes_per_post,
  fu.total_favorites,
  fu.total_bounty,
  fu.total_comments,
  fu.total_dupe_links,
  fu.total_closes,
  fu.total_reopens,
  fu.gold_badges,
  fu.silver_badges,
  fu.bronze_badges,
  fu.tag_badges,
  fu.loc_median_net_votes,
  fu.avg_posts_loc,
  fu.users_in_loc,
  ra.last_3mo_qs,
  ra.last_3mo_as,
  ra.last_3mo_up,
  ra.last_3mo_down,
  -- location-relative performance
  case when fu.loc_median_net_votes is null then null
       else fu.net_votes - fu.loc_median_net_votes end as net_votes_vs_loc_median,
  -- categorical bucket example
  case
    when fu.total_posts >= 500 then 'whale'
    when fu.total_posts >= 100 then 'power'
    when fu.total_posts >= 20 then 'regular'
    when fu.total_posts >= 1 then 'newbie'
    else 'lurker'
  end as contribution_bucket,
  -- string manipulations and null logic
  concat_ws(' - ',
    nullif(trim(coalesce(fu.displayname, 'Anonymous')),''),
    case when fu.location_norm is null or fu.location_norm = 'Unknown' then 'Nowhere' else fu.location_norm end
  ) as label,
  -- correlated scalar subqueries
  (
    select coalesce(avg(p.score),0)
    from posts p
    where p.owneruserid = fu.user_id
      and p.posttypeid = 1
      and p.creationdate >= (select start_month from params)
  ) as avg_q_score_total_window,
  (
    select coalesce(avg(p.score),0)
    from posts p
    where p.owneruserid = fu.user_id
      and p.posttypeid = 2
      and p.creationdate >= (select start_month from params)
  ) as avg_a_score_total_window
from final_users fu
left join recent_activity ra on ra.user_id = fu.user_id
where coalesce(fu.total_posts,0) > 0
  and (fu.net_votes_per_post is null or fu.net_votes_per_post >= -5.0)
  and (fu.location_norm is null or fu.users_in_loc >= 3)
order by fu.net_vote_rank nulls last, fu.volume_rank nulls last, fu.user_id
limit 500;