-- {"query": "119.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2876}
with params as (
  select
    date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '24 months' as start_month,
    date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) as end_month
),
months as (
  select cast(generate_series(start_month, end_month, interval '1 month') as timestamp) :: timestamp as m_ts
  from params
),
months_dates as (
  select cast(date_trunc('month', m_ts) as date) as m
  from months
),
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    cast(date_trunc('month', u.creationdate) as date) as created_month,
    u.reputation,
    u.upvotes,
    u.downvotes,
    u.views
  from users u
),
post_core as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    cast(date_trunc('month', p.creationdate) as date) as created_month,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    cast(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end as integer) as has_accepted_ans
  from posts p
  where p.creationdate is not null
),
comment_core as (
  select
    c.postid,
    cast(date_trunc('month', c.creationdate) as date) as created_month,
    count(*) as comments_in_month,
    sum(greatest(c.score, 0)) as nonneg_comment_score
  from comments c
  where c.creationdate is not null
  group by c.postid, cast(date_trunc('month', c.creationdate) as date)
),
vote_core as (
  select
    v.postid,
    cast(date_trunc('month', v.creationdate) as date) as created_month,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_paid
  from votes v
  where v.creationdate is not null
  group by v.postid, cast(date_trunc('month', v.creationdate) as date)
),
dup_links as (
  select
    pl.postid,
    cast(date_trunc('month', pl.creationdate) as date) as created_month,
    count(case when pl.linktypeid = 3 then 1 end) as dup_links_count
  from postlinks pl
  where pl.creationdate is not null
  group by pl.postid, cast(date_trunc('month', pl.creationdate) as date)
),
close_events as (
  select
    ph.postid,
    cast(date_trunc('month', ph.creationdate) as date) as created_month,
    count(case when ph.posthistorytypeid = 10 then 1 end) as closes,
    count(case when ph.posthistorytypeid = 11 then 1 end) as reopens
  from posthistory ph
  where ph.posthistorytypeid in (10,11) and ph.creationdate is not null
  group by ph.postid, cast(date_trunc('month', ph.creationdate) as date)
),
tag_explode as (
  select
    pc.id as post_id,
    pc.created_month,
    unnest(string_to_array(substring(pc.tags, 2, greatest(char_length(pc.tags)-2,0)), '><')) as tagname
  from post_core pc
  where pc.posttypeid = 1
    and pc.tags is not null
),
tag_rank as (
  select
    te.created_month,
    te.tagname,
    count(*) as tag_uses,
    row_number() over (partition by te.created_month order by count(*) desc, te.tagname) as rn
  from tag_explode te
  group by te.created_month, te.tagname
),
per_post_month as (
  select
    m.m as bucket,
    pc.id as post_id,
    pc.posttypeid,
    pc.owneruserid,
    pc.score,
    pc.viewcount,
    pc.answercount,
    pc.favoritecount,
    pc.commentcount,
    pc.has_accepted_ans,
    coalesce(vc.net_votes, 0) as net_votes,
    coalesce(vc.bounty_started, 0) as bounty_started,
    coalesce(vc.bounty_paid, 0) as bounty_paid,
    coalesce(cc.comments_in_month, 0) as comments_in_month,
    coalesce(cc.nonneg_comment_score, 0) as nonneg_comment_score,
    coalesce(dl.dup_links_count, 0) as dup_links_count,
    coalesce(ce.closes, 0) as closes,
    coalesce(ce.reopens, 0) as reopens
  from months_dates m
  left join post_core pc
    on pc.created_month = m.m
  left join vote_core vc
    on vc.postid = pc.id and vc.created_month = m.m
  left join comment_core cc
    on cc.postid = pc.id and cc.created_month = m.m
  left join dup_links dl
    on dl.postid = pc.id and dl.created_month = m.m
  left join close_events ce
    on ce.postid = pc.id and ce.created_month = m.m
),
user_month_roll as (
  select
    ppm.bucket,
    ua.user_id,
    ua.displayname,
    ua.location_norm,
    sum(case when ppm.posttypeid = 1 then 1 else 0 end) as questions,
    sum(case when ppm.posttypeid = 2 then 1 else 0 end) as answers,
    sum(coalesce(ppm.score,0)) as sum_score,
    sum(coalesce(ppm.viewcount,0)) as sum_views,
    sum(coalesce(ppm.answercount,0)) as sum_answercount,
    sum(coalesce(ppm.favoritecount,0)) as sum_favs,
    sum(coalesce(ppm.commentcount,0)) as sum_post_comments,
    sum(coalesce(ppm.comments_in_month,0)) as sum_comments_created_on_posts,
    sum(coalesce(ppm.net_votes,0)) as sum_net_votes,
    sum(coalesce(ppm.bounty_started,0)) as sum_bounty_started,
    sum(coalesce(ppm.bounty_paid,0)) as sum_bounty_paid,
    sum(coalesce(ppm.has_accepted_ans,0)) as accepted_flags,
    sum(coalesce(ppm.dup_links_count,0)) as dup_links_count,
    sum(coalesce(ppm.closes,0)) as closes,
    sum(coalesce(ppm.reopens,0)) as reopens
  from per_post_month ppm
  left join user_activity ua
    on ua.user_id = ppm.owneruserid
  group by ppm.bucket, ua.user_id, ua.displayname, ua.location_norm
),
user_lag as (
  select
    umr.bucket,
    umr.user_id,
    umr.displayname,
    umr.location_norm,
    umr.questions,
    umr.answers,
    umr.sum_score,
    umr.sum_views,
    umr.sum_answercount,
    umr.sum_favs,
    umr.sum_post_comments,
    umr.sum_comments_created_on_posts,
    umr.sum_net_votes,
    umr.sum_bounty_started,
    umr.sum_bounty_paid,
    umr.accepted_flags,
    umr.dup_links_count,
    umr.closes,
    umr.reopens,
    lag(umr.sum_score) over (partition by umr.user_id order by umr.bucket) as prev_sum_score,
    lag(umr.sum_views) over (partition by umr.user_id order by umr.bucket) as prev_sum_views,
    lag(umr.sum_net_votes) over (partition by umr.user_id order by umr.bucket) as prev_sum_net_votes
  from user_month_roll umr
),
month_agg as (
  select
    ppm.bucket,
    count(case when ppm.posttypeid = 1 then 1 end) as question_posts,
    count(case when ppm.posttypeid = 2 then 1 end) as answer_posts,
    count(case when ppm.posttypeid not in (1,2) or ppm.posttypeid is null then 1 end) as other_posts,
    sum(coalesce(ppm.score,0)) as total_score,
    avg(nullif(ppm.viewcount,0)) as avg_viewcount_nonzero,
    sum(case when ppm.posttypeid = 1 then coalesce(ppm.answercount,0) else 0 end) as answers_to_questions,
    sum(coalesce(ppm.has_accepted_ans,0)) as accepted_questions,
    sum(coalesce(ppm.dup_links_count,0)) as dup_links,
    sum(coalesce(ppm.closes,0)) as close_events,
    sum(coalesce(ppm.reopens,0)) as reopen_events,
    percentile_cont(0.5) within group (order by coalesce(ppm.score,0)) as median_post_score
  from per_post_month ppm
  group by ppm.bucket
),
top_tags as (
  select
    tr.created_month as bucket,
    string_agg(tr.tagname, ', ' order by tr.rn) as top5_tags
  from tag_rank tr
  where tr.rn <= 5
  group by tr.created_month
),
power_users as (
  select
    ul.bucket,
    ul.user_id,
    coalesce(ul.displayname, ('anon#' || cast(ul.user_id as text))) as displayname,
    ul.location_norm,
    ul.questions,
    ul.answers,
    ul.sum_score,
    ul.sum_views,
    ul.sum_net_votes,
    ul.sum_bounty_paid,
    rank() over (partition by ul.bucket order by coalesce(ul.sum_score,0) desc, coalesce(ul.sum_views,0) desc, ul.user_id) as score_rank,
    case
      when ul.prev_sum_score is null then null
      when coalesce(ul.sum_score,0) > coalesce(ul.prev_sum_score,0) then 'up'
      when coalesce(ul.sum_score,0) < coalesce(ul.prev_sum_score,0) then 'down'
      else 'flat'
    end as score_trend
  from user_lag ul
),
power_users_top as (
  select *
  from power_users
  where score_rank <= 10
),
user_badges_month as (
  select
    cast(date_trunc('month', b.date) as date) as bucket,
    b.userid,
    count(*) as badges_awarded,
    sum(case when b.class = 1 then 1 else 0 end) as golds,
    sum(case when b.class = 2 then 1 else 0 end) as silvers,
    sum(case when b.class = 3 then 1 else 0 end) as bronzes
  from badges b
  where b.date is not null
  group by cast(date_trunc('month', b.date) as date), b.userid
),
final as (
  select
    m.m as bucket,
    ma.question_posts,
    ma.answer_posts,
    ma.other_posts,
    ma.total_score,
    ma.avg_viewcount_nonzero,
    ma.answers_to_questions,
    ma.accepted_questions,
    ma.dup_links,
    ma.close_events,
    ma.reopen_events,
    ma.median_post_score,
    coalesce(tt.top5_tags, '(none)') as top5_tags,
    put.user_id,
    put.displayname,
    put.location_norm,
    put.questions,
    put.answers,
    put.sum_score,
    put.sum_views,
    put.sum_net_votes,
    put.sum_bounty_paid,
    put.score_rank,
    put.score_trend,
    coalesce(ubm.badges_awarded,0) as badges_awarded,
    coalesce(ubm.golds,0) as golds,
    coalesce(ubm.silvers,0) as silvers,
    coalesce(ubm.bronzes,0) as bronzes
  from months_dates m
  left join month_agg ma
    on ma.bucket = m.m
  left join top_tags tt
    on tt.bucket = m.m
  left join power_users_top put
    on put.bucket = m.m
  left join user_badges_month ubm
    on ubm.bucket = m.m and ubm.userid = put.user_id
),
with_totals as (
  select
    f.bucket,
    f.question_posts,
    f.answer_posts,
    f.other_posts,
    f.total_score,
    f.avg_viewcount_nonzero,
    f.answers_to_questions,
    f.accepted_questions,
    f.dup_links,
    f.close_events,
    f.reopen_events,
    f.median_post_score,
    f.top5_tags,
    f.user_id,
    f.displayname,
    f.location_norm,
    f.questions,
    f.answers,
    f.sum_score,
    f.sum_views,
    f.sum_net_votes,
    f.sum_bounty_paid,
    f.score_rank,
    f.score_trend,
    f.badges_awarded,
    f.golds,
    f.silvers,
    f.bronzes,
    sum(coalesce(f.total_score,0)) over (order by f.bucket rows between unbounded preceding and current row) as running_total_score,
    sum(coalesce(f.answer_posts,0)) over (order by f.bucket rows between unbounded preceding and current row) as running_answers,
    sum(coalesce(f.question_posts,0)) over (order by f.bucket rows between unbounded preceding and current row) as running_questions,
    case when f.question_posts > 0 then round((cast(f.accepted_questions as numeric) / f.question_posts) * 100, 2) else null end as acceptance_rate_pct,
    case when f.answer_posts > 0 then round((cast(f.answers_to_questions as numeric) / f.answer_posts) * 1.0, 2) else null end as answers_per_answerpost_ratio
  from final f
)
select
  wt.bucket,
  wt.top5_tags,
  wt.question_posts,
  wt.answer_posts,
  wt.other_posts,
  wt.total_score,
  wt.median_post_score,
  wt.avg_viewcount_nonzero,
  wt.answers_to_questions,
  wt.accepted_questions,
  wt.dup_links,
  wt.close_events,
  wt.reopen_events,
  wt.running_total_score,
  wt.running_answers,
  wt.running_questions,
  wt.acceptance_rate_pct,
  wt.answers_per_answerpost_ratio,
  coalesce(wt.user_id, -1) as user_id,
  wt.displayname,
  wt.location_norm,
  wt.questions as user_questions,
  wt.answers as user_answers,
  wt.sum_score as user_sum_score,
  wt.sum_views as user_sum_views,
  wt.sum_net_votes as user_sum_net_votes,
  wt.sum_bounty_paid as user_sum_bounty_paid,
  wt.score_rank as user_score_rank,
  wt.score_trend as user_score_trend,
  wt.badges_awarded as user_badges_awarded,
  wt.golds as user_golds,
  wt.silvers as user_silvers,
  wt.bronzes as user_bronzes
from with_totals wt
where wt.bucket between (select date_trunc('month', start_month)::date from params) and (select date_trunc('month', end_month)::date from params)
order by wt.bucket asc, wt.score_rank nulls last, wt.user_id asc;