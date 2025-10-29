-- {"query": "245.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2561}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    cast(u.creationdate as date) as signup_date,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(case when p.posttypeid = 1 then 1 end) as questions,
    count(case when p.posttypeid = 2 then 1 end) as answers,
    sum(coalesce(p.score,0)) as post_score,
    sum(case when p.posttypeid = 1 then coalesce(p.viewcount,0) else 0 end) as question_views,
    max(p.lastactivitydate) as last_post_activity,
    count(distinct case when p.posttypeid in (1,2) and p.closeddate is not null then p.id end) as closed_posts
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_agg as (
  select
    c.userid as user_id,
    count(*) as comments,
    sum(coalesce(c.score,0)) as comment_score,
    min(c.creationdate) as first_comment_at,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_agg as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    count(case when b.tagbased = true then 1 end) as tag_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
vote_agg as (
  select
    v.userid as user_id,
    count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
    count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
    count(case when v.votetypeid in (8,9) then 1 end) as bounties_events,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount_total,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.userid is not null
  group by v.userid
),
accepted_answers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers_count,
    sum(coalesce(a.score,0)) as accepted_answers_score
  from posts q
  join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
  group by a.owneruserid
),
dup_closures as (
  select
    ph.userid as user_id,
    count(*) as duplicate_close_votes,
    max(ph.creationdate) as last_dup_close_at
  from posthistory ph
  where ph.posthistorytypeid in (10,35) and ph.comment in ('1','101')
  group by ph.userid
),
tag_usage as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')) as tag
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tag_per_user as (
  select user_id, tag, tag_cnt, rank() over (partition by user_id order by tag_cnt desc, tag) as rnk
  from (
    select user_id, lower(tag) as tag, count(*) as tag_cnt
    from tag_usage
    group by user_id, lower(tag)
  ) s
),
linked_graph as (
  select
    p.owneruserid as user_id,
    count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as links_out,
    count(distinct case when pl.linktypeid = 3 then pl.postid end) as dup_marked
  from postlinks pl
  join posts p on p.id = pl.postid and p.owneruserid is not null
  group by p.owneruserid
),
activity_calendar as (
  select
    pa.owneruserid as user_id,
    cast(date_trunc('month', pa.creationdate) as date) as month_bucket,
    count(*) as posts_in_month,
    sum(coalesce(pa.score,0)) as score_in_month
  from posts pa
  where pa.owneruserid is not null and pa.creationdate >= (select max(creationdate) - interval '365 days' from posts)
  group by pa.owneruserid, date_trunc('month', pa.creationdate)
),
activity_variance as (
  select
    user_id,
    avg(posts_in_month) as avg_posts_month,
    stddev_samp(posts_in_month) as std_posts_month,
    avg(score_in_month) as avg_score_month,
    stddev_samp(score_in_month) as std_score_month
  from activity_calendar
  group by user_id
),
user_ranked as (
  select
    ru.user_id,
    ru.displayname,
    ru.location_norm,
    ua.questions,
    ua.answers,
    ua.post_score,
    coalesce(aa.accepted_answers_count,0) as accepted_answers_count,
    coalesce(aa.accepted_answers_score,0) as accepted_answers_score,
    coalesce(ca.comments,0) as comments,
    coalesce(ca.comment_score,0) as comment_score,
    coalesce(ba.total_badges,0) as total_badges,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.tag_badges,0) as tag_badges,
    coalesce(va.upvotes_cast,0) as upvotes_cast,
    coalesce(va.downvotes_cast,0) as downvotes_cast,
    coalesce(va.bounty_amount_total,0) as bounty_amount_total,
    coalesce(dc.duplicate_close_votes,0) as duplicate_close_votes,
    coalesce(lg.links_out,0) as links_out,
    coalesce(lg.dup_marked,0) as dup_marked,
    av.avg_posts_month,
    av.std_posts_month,
    av.avg_score_month,
    av.std_score_month,
    tt.tag as top_tag,
    tt.tag_cnt as top_tag_count,
    case when coalesce(ua.answers,0) > 0 then round(100.0 * coalesce(aa.accepted_answers_count,0) / ua.answers, 2) end as accept_rate_pct,
    case
      when coalesce(ua.questions,0) + coalesce(ua.answers,0) + coalesce(ca.comments,0) > 0
        then round(
          (coalesce(ua.post_score,0) + coalesce(ca.comment_score,0))
          / (coalesce(ua.questions,0) + coalesce(ua.answers,0) + coalesce(ca.comments,0))
        , 3)
    end as avg_score_per_contribution,
    ru.reputation
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join comment_agg ca on ca.user_id = ru.user_id
  left join badge_agg ba on ba.user_id = ru.user_id
  left join vote_agg va on va.user_id = ru.user_id
  left join accepted_answers aa on aa.user_id = ru.user_id
  left join dup_closures dc on dc.user_id = ru.user_id
  left join linked_graph lg on lg.user_id = ru.user_id
  left join activity_variance av on av.user_id = ru.user_id
  left join lateral (
    select tag, tag_cnt from top_tag_per_user t
    where t.user_id = ru.user_id and t.rnk = 1
    limit 1
  ) tt on true
),
score_band as (
  select
    ur.*,
    ntile(10) over (order by coalesce(ur.post_score,0) desc nulls last) as score_decile,
    row_number() over (order by coalesce(ur.post_score,0) desc nulls last, coalesce(ur.answers,0) desc, ur.user_id) as global_rank
  from user_ranked ur
),
peer_stats as (
  select
    sb.user_id,
    sb.score_decile,
    avg(sb.accept_rate_pct) over (partition by sb.score_decile) as peer_accept_rate_avg,
    (select percentile_disc(0.5) within group (order by s2.avg_score_per_contribution)
     from score_band s2
     where s2.score_decile = sb.score_decile) as peer_median_avg_score_per_contrib
  from score_band sb
  group by sb.user_id, sb.score_decile, sb.accept_rate_pct, sb.avg_score_per_contribution
)
select
  sb.global_rank,
  sb.score_decile,
  sb.user_id,
  sb.displayname,
  sb.location_norm,
  coalesce(sb.questions,0) as questions,
  coalesce(sb.answers,0) as answers,
  coalesce(sb.post_score,0) as post_score,
  coalesce(sb.accepted_answers_count,0) as accepted_answers_count,
  coalesce(sb.accepted_answers_score,0) as accepted_answers_score,
  coalesce(sb.comments,0) as comments,
  coalesce(sb.comment_score,0) as comment_score,
  coalesce(sb.total_badges,0) as total_badges,
  sb.gold_badges,
  sb.silver_badges,
  sb.bronze_badges,
  sb.tag_badges,
  sb.upvotes_cast,
  sb.downvotes_cast,
  sb.bounty_amount_total,
  sb.duplicate_close_votes,
  sb.links_out,
  sb.dup_marked,
  coalesce(sb.avg_posts_month,0) as avg_posts_month,
  coalesce(sb.std_posts_month,0) as std_posts_month,
  coalesce(sb.avg_score_month,0) as avg_score_month,
  coalesce(sb.std_score_month,0) as std_score_month,
  coalesce(sb.top_tag, 'n/a') as top_tag,
  coalesce(sb.top_tag_count,0) as top_tag_count,
  sb.accept_rate_pct,
  sb.avg_score_per_contribution,
  ps.peer_accept_rate_avg,
  ps.peer_median_avg_score_per_contrib,
  case
    when sb.reputation >= 100000 then 'Legend'
    when sb.reputation >= 50000 then 'Guru'
    when sb.reputation >= 10000 then 'Expert'
    when sb.reputation >= 1000 then 'Contributor'
    else 'Newbie'
  end as rep_bucket,
  case
    when sb.answers is null and sb.questions is null and sb.comments is null then 'No activity'
    when coalesce(sb.answers,0) > coalesce(sb.questions,0) then 'Answerer'
    when coalesce(sb.questions,0) > 0 and coalesce(sb.answers,0) = 0 then 'Questioner'
    else 'Mixed'
  end as activity_profile
from score_band sb
left join peer_stats ps on ps.user_id = sb.user_id and ps.score_decile = sb.score_decile
where
  (sb.top_tag is null or length(sb.top_tag) >= 1)
  and coalesce(sb.downvotes_cast,0) <= coalesce(sb.upvotes_cast,0) * 5 + 50
  and (
    sb.accept_rate_pct is null
    or sb.accept_rate_pct >= (
      select percentile_disc(0.25) within group (order by x)
      from (
        select coalesce(accept_rate_pct,0) as x
        from score_band
      ) q
    )
  )
order by sb.score_decile asc, sb.global_rank asc
limit 500;