-- {"query": "618.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3238} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(greatest(p.score, 0)) as nonneg_score_sum,
    avg(nullif(p.viewcount, 0)) as avg_viewcount_nonzero,
    max(p.lastactivitydate) as last_post_activity,
    sum(coalesce(p.answercount, 0)) as total_answer_slots,
    sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as accepted_qs
  from recent_users u
  left join posts p
    on p.owneruserid = u.id
   and p.creationdate >= u.creationdate
  group by u.id
),
user_votes as (
  select
    u.id as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from recent_users u
  left join votes v
    on v.userid = u.id
   and v.creationdate >= u.creationdate
  group by u.id
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  where b.date >= (select min(ru.creationdate) from recent_users ru)
  group by b.userid
),
tag_dim as (
  select
    t.tagname,
    t.id,
    t.count as tag_count
  from tags t
),
question_tags as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
),
user_top_tags as (
  select
    p.owneruserid as user_id,
    qt.tagname,
    count(*) as tag_use_count,
    rank() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate) asc) as rnk
  from posts p
  join question_tags qt on qt.post_id = p.id
  where p.owneruserid is not null
  group by p.owneruserid, qt.tagname
),
dup_closure as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (10) and ph.comment in ('1','101')) as duplicate_closures,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_close_date
  from posthistory ph
  group by ph.postid
),
linked_graph as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_count
  from postlinks pl
  group by pl.postid
),
comment_stats as (
  select
    p.owneruserid as user_id,
    count(c.id) as comments_authored_on_own_posts,
    avg(c.score) as avg_comment_score_on_own_posts,
    max(c.creationdate) as last_comment_date_on_own_posts
  from posts p
  left join comments c on c.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
user_quality as (
  select
    ua.user_id,
    case
      when ua.q_count + ua.a_count = 0 then null
      else round( (ua.nonneg_score_sum::numeric) / nullif(ua.q_count + ua.a_count, 0), 3)
    end as avg_score_per_post,
    case
      when ua.total_answer_slots = 0 then null
      else round( (ua.accepted_qs::numeric) / nullif(ua.total_answer_slots, 0), 4)
    end as acceptance_ratio_est,
    least(1.0, coalesce( (ua.a_count::numeric) / nullif(ua.q_count,0), 0)) as answer_question_balance_capped
  from user_activity ua
),
posts_ranked as (
  select
    p.*,
    row_number() over (partition by p.owneruserid order by coalesce(p.score, -2147483648) desc, p.viewcount desc nulls last, p.creationdate desc) as rn_score_desc,
    row_number() over (partition by p.owneruserid order by coalesce(p.viewcount, -1) desc nulls last, p.score desc nulls last, p.creationdate desc) as rn_views_desc
  from posts p
  where p.owneruserid is not null
),
best_posts as (
  select
    pr.owneruserid as user_id,
    max(pr.score) as best_score,
    max(pr.viewcount) as best_views,
    max(pr.creationdate) filter (where pr.rn_score_desc = 1) as top_score_post_date,
    max(pr.creationdate) filter (where pr.rn_views_desc = 1) as top_view_post_date
  from posts_ranked pr
  group by pr.owneruserid
),
user_last_seen as (
  select
    u.id as user_id,
    max(coalesce(u.lastaccessdate, u.creationdate)) as last_seen
  from users u
  group by u.id
),
activity_calendar as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) as posts_in_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_variance as (
  select
    ac.user_id,
    stddev_pop(ac.posts_in_month) as posting_stddev,
    avg(ac.posts_in_month) as posting_avg
  from activity_calendar ac
  group by ac.user_id
),
power_users as (
  select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ua.q_count,
    ua.a_count,
    uv.upvotes_cast,
    uv.downvotes_cast,
    uv.bounty_events,
    uv.bounty_total,
    br.badges_total,
    br.gold_count,
    br.silver_count,
    br.bronze_count,
    br.tag_badges,
    dq.duplicate_closures as dup_closures_on_owned_posts,
    lg.linked_count,
    lg.duplicate_count,
    cs.comments_authored_on_own_posts,
    cs.avg_comment_score_on_own_posts,
    uq.avg_score_per_post,
    uq.acceptance_ratio_est,
    uq.answer_question_balance_capped,
    bp.best_score,
    bp.best_views,
    bp.top_score_post_date,
    bp.top_view_post_date,
    uls.last_seen,
    av.posting_stddev,
    av.posting_avg
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.id
  left join user_votes uv on uv.user_id = ru.id
  left join badge_rollup br on br.user_id = ru.id
  left join (
    select p.owneruserid as user_id,
           sum(coalesce(dc.duplicate_closures,0)) as duplicate_closures
    from posts p
    left join dup_closure dc on dc.postid = p.id
    group by p.owneruserid
  ) dq on dq.user_id = ru.id
  left join (
    select p.owneruserid as user_id,
           sum(coalesce(lg.linked_count,0)) as linked_count,
           sum(coalesce(lg.duplicate_count,0)) as duplicate_count
    from posts p
    left join linked_graph lg on lg.postid = p.id
    group by p.owneruserid
  ) lg on lg.user_id = ru.id
  left join comment_stats cs on cs.user_id = ru.id
  left join user_quality uq on uq.user_id = ru.id
  left join best_posts bp on bp.user_id = ru.id
  left join user_last_seen uls on uls.user_id = ru.id
  left join activity_variance av on av.user_id = ru.id
),
top_tag_final as (
  select
    utt.user_id,
    max(case when utt.rnk = 1 then utt.tagname end) as top_tag,
    max(case when utt.rnk = 2 then utt.tagname end) as second_tag
  from user_top_tags utt
  where utt.rnk <= 2
  group by utt.user_id
),
normalized as (
  select
    pu.*,
    ttf.top_tag,
    ttf.second_tag,
    case
      when pu.badges_total = 0 then null
      else round((pu.gold_count::numeric / pu.badges_total) * 100, 2)
    end as pct_gold_badges,
    case
      when coalesce(pu.upvotes_cast + pu.downvotes_cast, 0) = 0 then null
      else round((pu.upvotes_cast::numeric / nullif(pu.upvotes_cast + pu.downvotes_cast, 0)) * 100, 2)
    end as pct_upvote_bias,
    case
      when pu.posting_avg is not null and pu.posting_avg > 0 then round(pu.posting_stddev / pu.posting_avg, 3)
      else null
    end as posting_cv,
    case
      when pu.reputation <= 1 then 'new'
      when pu.reputation <= 100 then 'bronze-ish'
      when pu.reputation <= 1000 then 'silver-ish'
      else 'gold-ish'
    end as rep_bucket
  from power_users pu
  left join top_tag_final ttf on ttf.user_id = pu.user_id
),
ranked as (
  select
    n.*,
    row_number() over (
      partition by n.rep_bucket
      order by coalesce(n.avg_score_per_post, -1) desc,
               coalesce(n.best_views, -1) desc,
               coalesce(n.badges_total, -1) desc,
               n.reputation desc
    ) as bucket_rank,
    dense_rank() over (
      order by coalesce(n.avg_score_per_post, -1) desc,
               coalesce(n.best_score, -1) desc,
               coalesce(n.duplicate_count, -1) desc
    ) as global_rank
  from normalized n
),
filters as (
  select
    r.*
  from ranked r
  where
    -- engaged users: at least one post or at least 5 votes, but exclude obvious bots by missing display name
    ((coalesce(r.q_count,0) + coalesce(r.a_count,0)) > 0 or coalesce(r.upvotes_cast,0) + coalesce(r.downvotes_cast,0) >= 5)
    and nullif(trim(r.displayname), '') is not null
)
select
  f.user_id,
  f.displayname,
  f.reputation,
  f.rep_bucket,
  to_char(f.cohort_month, 'YYYY-MM') as cohort_month,
  coalesce(f.q_count,0) as questions,
  coalesce(f.a_count,0) as answers,
  coalesce(f.badges_total,0) as badges_total,
  coalesce(f.gold_count,0) as gold,
  coalesce(f.silver_count,0) as silver,
  coalesce(f.bronze_count,0) as bronze,
  coalesce(f.tag_badges,0) as tag_badges,
  coalesce(f.upvotes_cast,0) as upvotes_cast,
  coalesce(f.downvotes_cast,0) as downvotes_cast,
  coalesce(f.bounty_events,0) as bounty_events,
  coalesce(f.bounty_total,0) as bounty_total,
  f.pct_gold_badges,
  f.pct_upvote_bias,
  f.avg_score_per_post,
  f.acceptance_ratio_est,
  f.answer_question_balance_capped,
  f.best_score,
  f.best_views,
  f.top_tag,
  f.second_tag,
  coalesce(f.linked_count,0) as linked_refs_to_owned_posts,
  coalesce(f.duplicate_count,0) as duplicates_refs_to_owned_posts,
  coalesce(f.dup_closures_on_owned_posts,0) as duplicate_closure_events_on_owned_posts,
  f.posting_avg,
  f.posting_stddev,
  f.posting_cv,
  f.last_seen,
  f.bucket_rank,
  f.global_rank
from filters f
where
  -- diverse predicate to exercise planner
  (
    (f.rep_bucket in ('gold-ish','silver-ish') and coalesce(f.avg_score_per_post,0) > 1.5)
    or
    (f.rep_bucket = 'bronze-ish' and coalesce(f.badges_total,0) >= 3 and coalesce(f.pct_upvote_bias,50) between 40 and 90)
    or
    (f.rep_bucket = 'new' and coalesce(f.a_count,0) >= 1 and f.top_tag is not null)
  )
  and (
    f.top_tag is null
    or exists (
      select 1
      from tag_dim td
      where td.tagname = f.top_tag
        and td.tag_count > coalesce(f.badges_total,0) + coalesce(f.q_count,0)
    )
  )
  and (
    -- correlated check: user's top score post was linked at least once or has nonzero views
    exists (
      select 1
      from posts p
      left join linked_graph lg on lg.postid = p.id
      where p.owneruserid = f.user_id
        and (p.score = f.best_score or p.viewcount = f.best_views)
        and coalesce(lg.linked_count,0) + coalesce(lg.duplicate_count,0) >= 0
      limit 1
    )
  )
order by
  f.global_rank asc,
  f.bucket_rank asc,
  f.user_id asc
limit 500;