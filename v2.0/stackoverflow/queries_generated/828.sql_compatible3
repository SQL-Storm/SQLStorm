with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
    coalesce(u.views, 0) as profile_views,
    row_number() over (order by greatest(u.lastaccessdate, u.creationdate) desc, u.reputation desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
recent_posts as (
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
    p.closeddate,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 'Question'
         when p.posttypeid = 2 then 'Answer'
         else 'Other' end as post_kind
  from posts p
  where p.creationdate >= (select coalesce(min(lastaccessdate), cast('2024-10-01 12:34:56' as timestamp) - interval '18 months') from recent_users)
),
user_post_agg as (
  select
    ru.user_id,
    count(*) filter (where rp.post_kind = 'Question') as q_count,
    count(*) filter (where rp.post_kind = 'Answer') as a_count,
    avg(nullif(rp.score, 0)) as avg_nonzero_score,
    sum(coalesce(rp.viewcount, 0)) as total_views,
    max(rp.creationdate) as last_post_date,
    sum(case when rp.closeddate is not null then 1 else 0 end) as closed_posts,
    count(*) filter (
      where rp.post_kind = 'Question'
        and rp.tags is not null
        and position('><' in rp.tags) > 0
    ) as multi_tag_qs
  from recent_users ru
  left join recent_posts rp
    on rp.owneruserid = ru.user_id
  group by ru.user_id
),
comment_engagement as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score, 0)) as comment_score,
    max(c.creationdate) as last_comment_date,
    percentile_cont(0.5) within group (order by coalesce(c.score, 0)) as median_comment_score
  from comments c
  where c.creationdate >= (select min(creationdate) from recent_posts)
  group by c.userid
),
badge_agg as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    count(*) filter (where b.tagbased = true) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
vote_signals as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_given,
    count(*) filter (where v.votetypeid = 3) as downvotes_given,
    count(*) filter (where v.votetypeid = 5) as favorites_given,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(coalesce(v.bountyamount, 0)) as bounty_amount_total,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
link_graph as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    count(distinct pl.relatedpostid) as unique_targets,
    count(distinct pl.postid) as unique_sources
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
mod_events as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,31,33,34,50,52,53)) as mod_event_count,
    count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
    count(*) filter (where ph.posthistorytypeid in (11,13)) as restore_events,
    count(*) filter (where ph.posthistorytypeid in (52,53)) as hot_events,
    max(ph.creationdate) as last_event_date,
    count(distinct case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as distinct_close_reasons
  from posthistory ph
  join posts p on p.id = ph.postid
  group by p.owneruserid
),
user_tag_stats as (
  select
    q.owneruserid as user_id,
    sum(t.count) as global_tag_popularity_sum,
    avg(t.count) as avg_tag_popularity,
    count(*) as tagged_q_rows
  from posts q
  join lateral (
    select unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag_name
  ) ut on q.posttypeid = 1 and q.tags is not null and length(q.tags) > 2
  left join tags t on lower(t.tagname) = lower(ut.tag_name)
  group by q.owneruserid
),
answer_acceptance as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    count(*) filter (where exists (
      select 1
      from posts q
      where q.acceptedanswerid = a.id
    )) as accepted_answers,
    avg(extract(epoch from (
      (select q.creationdate from posts q where q.acceptedanswerid = a.id) - a.creationdate
    ))) filter (where exists (select 1 from posts q where q.acceptedanswerid = a.id)) as avg_accept_latency_seconds
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (select min(creationdate) from recent_posts)
  group by a.owneruserid
),
monthly_activity as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month_bucket,
    count(*) filter (where p.posttypeid = 1) as q_monthly,
    count(*) filter (where p.posttypeid = 2) as a_monthly,
    sum(greatest(coalesce(p.score,0),0)) as positive_score_sum
  from posts p
  where p.creationdate >= (select min(creationdate) from recent_posts)
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_momentum as (
  select
    ma.user_id,
    ma.month_bucket,
    q_monthly,
    a_monthly,
    positive_score_sum,
    sum(q_monthly + a_monthly) over (partition by ma.user_id order by month_bucket rows between 2 preceding and current row) as last_3mo_posts,
    avg(positive_score_sum) over (partition by ma.user_id order by month_bucket rows between 5 preceding and current row) as last_6mo_pos_score_avg,
    rank() over (partition by ma.user_id order by positive_score_sum desc, month_bucket desc) as best_month_rank
  from monthly_activity ma
),
momentum_snapshot as (
  select distinct on (user_id)
    user_id,
    month_bucket as recent_month,
    last_3mo_posts,
    last_6mo_pos_score_avg,
    best_month_rank
  from activity_momentum
  order by user_id, month_bucket desc
),
cohort_candidates as (
  select user_id from recent_users where rn <= 500
  union
  select user_id from user_post_agg where total_views > 50000
  union
  select user_id from badge_agg where gold_count >= 3
  union
  select user_id from vote_signals where bounty_amount_total >= 100
),
engagement_score as (
  select
    u.user_id,
    (
      coalesce(ln(nullif(upa.total_views,0) + 1), 0)
      + coalesce(upa.q_count * 0.6 + upa.a_count * 1.0, 0)
      + coalesce(ces.comment_score * 0.05, 0)
      + coalesce(ba.gold_count * 3 + ba.silver_count * 1.5 + ba.bronze_count * 0.5, 0)
      + coalesce(vs.upvotes_given * 0.1 - vs.downvotes_given * 0.2, 0)
      + coalesce(lg.related_links * 0.05 + lg.duplicate_links * -0.1, 0)
      + coalesce(me.hot_events * 2 - me.closed_events * 0.5, 0)
      + coalesce(ms.last_3mo_posts * 0.8 + greatest(ms.last_6mo_pos_score_avg, 0) * 0.2, 0)
      + coalesce(case when ua.answers_total is not null and ua.answers_total <> 0 then cast(ua.accepted_answers as double precision) / ua.answers_total end, 0) * 5
      + coalesce(case when ua.avg_accept_latency_seconds is not null and ua.avg_accept_latency_seconds <> 0 then 1.0 / ua.avg_accept_latency_seconds end, 0) * 1000
      + coalesce(uts.avg_tag_popularity / nullif(greatest(upa.q_count,1),0), 0) * 0.001
    ) as engagement_score
  from cohort_candidates u
  left join user_post_agg upa on upa.user_id = u.user_id
  left join comment_engagement ces on ces.user_id = u.user_id
  left join badge_agg ba on ba.user_id = u.user_id
  left join vote_signals vs on vs.user_id = u.user_id
  left join link_graph lg on lg.user_id = u.user_id
  left join mod_events me on me.user_id = u.user_id
  left join momentum_snapshot ms on ms.user_id = u.user_id
  left join answer_acceptance ua on ua.user_id = u.user_id
  left join user_tag_stats uts on uts.user_id = u.user_id
),
user_top_tag as (
  select
    q.owneruserid as user_id,
    (select ut2.tag_name
     from (
       select unnest(string_to_array(substring(q2.tags, 2, length(q2.tags)-2), '><')) as tag_name
       from posts q2
       where q2.owneruserid = q.owneruserid and q2.posttypeid = 1 and q2.tags is not null and length(q2.tags) > 2
     ) ut2
     group by ut2.tag_name
     order by count(*) desc, min(ut2.tag_name) asc
     limit 1) as top_tag
  from posts q
  where q.posttypeid = 1 and q.tags is not null and length(q.tags) > 2
  group by q.owneruserid
),
controversy as (
  select
    q.owneruserid as user_id,
    count(*) filter (where q.score <= 0 and coalesce(q.commentcount,0) >= 5) as low_score_high_discussion,
    count(*) filter (where q.closeddate is not null and coalesce(q.viewcount,0) >= 1000) as closed_high_view,
    avg(coalesce(q.viewcount,0)) filter (where q.closeddate is not null) as avg_views_closed_q
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
percentiles as (
  select
    (select percentile_disc(0.5) within group (order by engagement_score) from engagement_score) as p50,
    (select percentile_disc(0.75) within group (order by engagement_score) from engagement_score) as p75,
    (select percentile_disc(0.9) within group (order by engagement_score) from engagement_score) as p90
)
select
  ru.user_id,
  coalesce(ru.displayname, concat('user-', cast(ru.user_id as varchar))) as displayname,
  ru.reputation,
  ru.creationdate,
  ru.lastaccessdate,
  ru.net_votes,
  ru.profile_views,
  upa.q_count,
  upa.a_count,
  upa.avg_nonzero_score,
  upa.total_views,
  upa.last_post_date,
  upa.closed_posts,
  upa.multi_tag_qs,
  coalesce(ces.comment_count, 0) as comment_count,
  coalesce(ces.comment_score, 0) as comment_score,
  ces.median_comment_score,
  coalesce(ba.badge_count, 0) as badge_count,
  coalesce(ba.gold_count, 0) as gold_badges,
  coalesce(ba.silver_count, 0) as silver_badges,
  coalesce(ba.bronze_count, 0) as bronze_badges,
  coalesce(vs.upvotes_given, 0) as upvotes_given,
  coalesce(vs.downvotes_given, 0) as downvotes_given,
  coalesce(vs.favorites_given, 0) as favorites_given,
  coalesce(vs.bounty_events, 0) as bounty_events,
  coalesce(vs.bounty_amount_total, 0) as bounty_amount_total,
  coalesce(lg.related_links, 0) as related_links,
  coalesce(lg.duplicate_links, 0) as duplicate_links,
  coalesce(lg.unique_targets, 0) as unique_link_targets,
  coalesce(lg.unique_sources, 0) as unique_link_sources,
  coalesce(me.mod_event_count, 0) as mod_event_count,
  coalesce(me.closed_events, 0) as closed_events,
  coalesce(me.restore_events, 0) as restore_events,
  coalesce(me.hot_events, 0) as hot_events,
  me.last_event_date,
  me.distinct_close_reasons,
  ms.recent_month,
  ms.last_3mo_posts,
  ms.last_6mo_pos_score_avg,
  ms.best_month_rank,
  coalesce(ua.answers_total, 0) as answers_total,
  coalesce(ua.accepted_answers, 0) as accepted_answers,
  ua.avg_accept_latency_seconds,
  uts.global_tag_popularity_sum,
  uts.avg_tag_popularity,
  uts.tagged_q_rows,
  utt.top_tag,
  cont.low_score_high_discussion,
  cont.closed_high_view,
  cont.avg_views_closed_q,
  es.engagement_score,
  case
    when es.engagement_score is null then 'Unknown'
    when es.engagement_score >= (select p90 from percentiles) then 'Elite'
    when es.engagement_score >= (select p75 from percentiles) then 'High'
    when es.engagement_score >= (select p50 from percentiles) then 'Medium'
    else 'Low'
  end as engagement_bucket
from cohort_candidates cc
join recent_users ru on ru.user_id = cc.user_id
left join user_post_agg upa on upa.user_id = ru.user_id
left join comment_engagement ces on ces.user_id = ru.user_id
left join badge_agg ba on ba.user_id = ru.user_id
left join vote_signals vs on vs.user_id = ru.user_id
left join link_graph lg on lg.user_id = ru.user_id
left join mod_events me on me.user_id = ru.user_id
left join momentum_snapshot ms on ms.user_id = ru.user_id
left join answer_acceptance ua on ua.user_id = ru.user_id
left join user_tag_stats uts on uts.user_id = ru.user_id
left join user_top_tag utt on utt.user_id = ru.user_id
left join controversy cont on cont.user_id = ru.user_id
left join engagement_score es on es.user_id = ru.user_id
where coalesce(upa.q_count,0) + coalesce(upa.a_count,0) > 0
order by es.engagement_score desc nulls last, ru.reputation desc
limit 250;