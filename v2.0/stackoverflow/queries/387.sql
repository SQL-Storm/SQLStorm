with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as cohort_rank
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '36 months'
),
user_badges as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) as total_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
user_posts as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.viewcount, 0)) as total_views,
    sum(coalesce(p.score, 0)) as total_post_score,
    max(p.creationdate) as last_post_at
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_comments as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score, 0)) as comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
user_votes as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    sum(coalesce(v.bountyamount, 0)) as bounty_spent,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.userid is not null
  group by v.userid
),
question_metrics as (
  select
    q.owneruserid as user_id,
    count(*) as questions_total,
    count(*) filter (where q.acceptedanswerid is not null) as questions_accepted,
    avg(nullif(q.answercount, 0)) as avg_answers_per_q,
    avg(coalesce(q.score, 0)) as avg_q_score
  from posts q
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    count(*) filter (where exists (select 1 from posts q where q.id = a.parentid and q.acceptedanswerid = a.id)) as answers_accepted,
    avg(coalesce(a.score, 0)) as avg_a_score
  from posts a
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
tag_activity as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tags as (
  select
    ta.user_id,
    ta.tagname,
    count(*) as uses,
    row_number() over (partition by ta.user_id order by count(*) desc, ta.tagname) as rn
  from tag_activity ta
  group by ta.user_id, ta.tagname
),
dupe_closures as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    count(*) as close_events
  from posthistory ph
  where ph.posthistorytypeid = 10
    and (ph.comment in ('1','101') or ph.text like '%OriginalQuestionIds%' or ph.text like '%Duplicate%')
  group by ph.postid
),
linked_graph as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate_link
  from postlinks pl
),
activity_unioned as (
  select u.id as user_id, u.creationdate as activity_at, 'user_created' as activity_type from users u
  union all
  select p.owneruserid, p.creationdate, 'post_created' from posts p where p.owneruserid is not null
  union all
  select c.userid, c.creationdate, 'comment_created' from comments c where c.userid is not null
  union all
  select v.userid, v.creationdate, 'vote_cast' from votes v where v.userid is not null
),
activity_agg as (
  select
    au.user_id,
    date_trunc('month', au.activity_at) as month_bucket,
    count(*) as actions_in_month,
    count(*) filter (where au.activity_type = 'post_created') as posts_in_month,
    count(*) filter (where au.activity_type = 'comment_created') as comments_in_month
  from activity_unioned au
  group by au.user_id, date_trunc('month', au.activity_at)
),
activity_rank as (
  select
    aa.user_id,
    aa.month_bucket,
    aa.actions_in_month,
    aa.posts_in_month,
    aa.comments_in_month,
    dense_rank() over (partition by aa.user_id order by aa.month_bucket desc) as recency_rank,
    sum(actions_in_month) over (partition by aa.user_id order by aa.month_bucket rows between unbounded preceding and current row) as cumulative_actions
  from activity_agg aa
),
post_score_percentiles as (
  select
    p.owneruserid as user_id,
    percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score,
    percentile_cont(0.9) within group (order by coalesce(p.score,0)) as p90_post_score
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
complex_predicate_users as (
  select
    u.id as user_id,
    case
      when (coalesce(u.websiteurl,'') ilike '%github%' or coalesce(u.aboutme,'') ilike '%open%source%')
       and (u.upvotes - u.downvotes) > 0
       and (u.reputation >= 1000 or (u.views is not null and u.views > 10000))
      then 1 else 0
    end as likely_contributor_flag
  from users u
),
user_dupe_exposure as (
  select
    p.owneruserid as user_id,
    count(distinct d.postid) as questions_closed_duplicate,
    count(distinct case when lg.is_duplicate_link = 1 then lg.postid end) as has_duplicate_link_out,
    count(distinct case when lg.is_duplicate_link = 1 then lg.relatedpostid end) as has_duplicate_link_in
  from posts p
  left join dupe_closures d on d.postid = p.id
  left join linked_graph lg on lg.postid = p.id or lg.relatedpostid = p.id
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid
),
accepted_answer_latency as (
  select
    q.owneruserid as user_id,
    avg(extract(epoch from (a.creationdate - q.creationdate))/3600.0) as avg_hours_to_first_answer,
    avg(extract(epoch from (acc.creationdate - q.creationdate))/3600.0) as avg_hours_to_accepted_answer
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  left join posts acc on acc.id = q.acceptedanswerid
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
user_last_activity as (
  select
    u.id as user_id,
    greatest(
      coalesce(up.last_post_at, cast('1970-01-01 00:00:00' as timestamp)),
      coalesce(uc.last_comment_at, cast('1970-01-01 00:00:00' as timestamp)),
      coalesce(uv.last_vote_at, cast('1970-01-01 00:00:00' as timestamp)),
      u.lastaccessdate
    ) as last_activity_at
  from users u
  left join user_posts up on up.user_id = u.id
  left join user_comments uc on uc.user_id = u.id
  left join user_votes uv on uv.user_id = u.id
),
score_change_window as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.creationdate,
    coalesce(p.score,0) as score,
    coalesce(p.viewcount,0) as views,
    sum(coalesce(p.score,0)) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as score_rolling_11,
    avg(coalesce(p.score,0)) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as score_avg_rolling_11,
    lead(p.score) over (partition by p.owneruserid order by p.creationdate) as next_score,
    lag(p.score) over (partition by p.owneruserid order by p.creationdate) as prev_score
  from posts p
  where p.owneruserid is not null
),
user_score_volatility as (
  select
    user_id,
    stddev_pop(score) as score_stddev,
    avg(score) as score_mean,
    count(*) as posts_count
  from score_change_window
  group by user_id
),
null_logic_sampler as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    nullif(regexp_replace(coalesce(u.displayname, ''), '\s+', ' ', 'g'), '') as displayname_norm,
    case when u.profileimageurl is null or u.profileimageurl = '' then 0 else 1 end as has_avatar
  from users u
),
final_scored as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.cohort_rank,
    nl.location_norm,
    nl.displayname_norm,
    nl.has_avatar,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(up.q_count,0) as q_count,
    coalesce(up.a_count,0) as a_count,
    coalesce(up.total_views,0) as total_views,
    coalesce(up.total_post_score,0) as total_post_score,
    coalesce(uc.comment_count,0) as comment_count,
    coalesce(uc.comment_score,0) as comment_score,
    coalesce(uv.upvotes_cast,0) as upvotes_cast,
    coalesce(uv.downvotes_cast,0) as downvotes_cast,
    coalesce(uv.favorites_cast,0) as favorites_cast,
    coalesce(uv.bounty_spent,0) as bounty_spent,
    coalesce(qm.questions_total,0) as questions_total,
    coalesce(qm.questions_accepted,0) as questions_accepted,
    coalesce(qm.avg_answers_per_q,0) as avg_answers_per_q,
    coalesce(qm.avg_q_score,0) as avg_q_score,
    coalesce(am.answers_total,0) as answers_total,
    coalesce(am.answers_accepted,0) as answers_accepted,
    coalesce(am.avg_a_score,0) as avg_a_score,
    coalesce(pt.median_post_score,0) as median_post_score,
    coalesce(pt.p90_post_score,0) as p90_post_score,
    coalesce(ud.questions_closed_duplicate,0) as questions_closed_duplicate,
    coalesce(ud.has_duplicate_link_out,0) as duplicate_links_out,
    coalesce(ud.has_duplicate_link_in,0) as duplicate_links_in,
    coalesce(aal.avg_hours_to_first_answer,0) as avg_hours_to_first_answer,
    coalesce(aal.avg_hours_to_accepted_answer,0) as avg_hours_to_accepted_answer,
    coalesce(usv.score_stddev,0) as score_stddev,
    coalesce(usv.score_mean,0) as score_mean,
    coalesce(usv.posts_count,0) as posts_count,
    clu.likely_contributor_flag,
    ula.last_activity_at,
    tt.tagname as top_tag_1,
    tt.uses as top_tag_1_uses,
    ar.actions_in_month as latest_actions,
    ar.posts_in_month as latest_posts,
    ar.comments_in_month as latest_comments
  from recent_users ru
  left join null_logic_sampler nl on nl.user_id = ru.user_id
  left join user_badges ub on ub.userid = ru.user_id
  left join user_posts up on up.user_id = ru.user_id
  left join user_comments uc on uc.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  left join question_metrics qm on qm.user_id = ru.user_id
  left join answer_metrics am on am.user_id = ru.user_id
  left join post_score_percentiles pt on pt.user_id = ru.user_id
  left join user_dupe_exposure ud on ud.user_id = ru.user_id
  left join accepted_answer_latency aal on aal.user_id = ru.user_id
  left join user_score_volatility usv on usv.user_id = ru.user_id
  left join complex_predicate_users clu on clu.user_id = ru.user_id
  left join user_last_activity ula on ula.user_id = ru.user_id
  left join lateral (
    select tagname, uses from top_tags t
    where t.user_id = ru.user_id and t.rn = 1
  ) tt on true
  left join lateral (
    select aa.actions_in_month, aa.posts_in_month, aa.comments_in_month
    from activity_rank aa
    where aa.user_id = ru.user_id and aa.recency_rank = 1
  ) ar on true
),
ranked as (
  select
    f.user_id,
    f.displayname,
    f.reputation,
    f.cohort_month,
    f.cohort_rank,
    f.location_norm,
    f.displayname_norm,
    f.has_avatar,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.total_badges,
    f.q_count,
    f.a_count,
    f.total_views,
    f.total_post_score,
    f.comment_count,
    f.comment_score,
    f.upvotes_cast,
    f.downvotes_cast,
    f.favorites_cast,
    f.bounty_spent,
    f.questions_total,
    f.questions_accepted,
    f.avg_answers_per_q,
    f.avg_q_score,
    f.answers_total,
    f.answers_accepted,
    f.avg_a_score,
    f.median_post_score,
    f.p90_post_score,
    f.questions_closed_duplicate,
    f.duplicate_links_out,
    f.duplicate_links_in,
    f.avg_hours_to_first_answer,
    f.avg_hours_to_accepted_answer,
    f.score_stddev,
    f.score_mean,
    f.posts_count,
    f.likely_contributor_flag,
    f.last_activity_at,
    f.top_tag_1,
    f.top_tag_1_uses,
    f.latest_actions,
    f.latest_posts,
    f.latest_comments,
    -- compute activity_power without dialect-specific casts
    (coalesce(f.total_post_score,0) + coalesce(f.comment_score,0) + (coalesce(f.gold_badges,0)*50 + coalesce(f.silver_badges,0)*10 + coalesce(f.bronze_badges,0)*3)
     + greatest(0, coalesce(f.upvotes_cast,0) - coalesce(f.downvotes_cast,0))
     + (case when f.likely_contributor_flag = 1 then 100 else 0 end)
     + least(200, coalesce(f.total_views,0)/100.0)
    ) as activity_power,
    row_number() over (
      partition by f.cohort_month
      order by
        (coalesce(f.total_post_score,0) + coalesce(f.comment_score,0) + (coalesce(f.gold_badges,0)*50 + coalesce(f.silver_badges,0)*10 + coalesce(f.bronze_badges,0)*3)
        + greatest(0, coalesce(f.upvotes_cast,0) - coalesce(f.downvotes_cast,0))
        + (case when f.likely_contributor_flag = 1 then 100 else 0 end)
        + least(200, coalesce(f.total_views,0)/100.0)
      ) desc, f.user_id
    ) as cohort_activity_rank
  from final_scored f
)
select
  r.user_id,
  r.displayname,
  r.displayname_norm,
  r.location_norm,
  r.has_avatar,
  r.cohort_month,
  r.cohort_rank,
  r.cohort_activity_rank,
  r.reputation,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.q_count,
  r.a_count,
  r.questions_total,
  r.questions_accepted,
  r.answers_total,
  r.answers_accepted,
  r.avg_answers_per_q,
  r.avg_q_score,
  r.avg_a_score,
  r.total_post_score,
  r.total_views,
  r.comment_count,
  r.comment_score,
  r.upvotes_cast,
  r.downvotes_cast,
  r.favorites_cast,
  r.bounty_spent,
  r.median_post_score,
  r.p90_post_score,
  r.questions_closed_duplicate,
  r.duplicate_links_out,
  r.duplicate_links_in,
  r.avg_hours_to_first_answer,
  r.avg_hours_to_accepted_answer,
  r.score_stddev,
  r.score_mean,
  r.posts_count,
  r.likely_contributor_flag,
  r.last_activity_at,
  r.top_tag_1,
  r.top_tag_1_uses,
  r.latest_actions,
  r.latest_posts,
  r.latest_comments,
  r.activity_power
from ranked r
where
  (r.cohort_activity_rank <= 100 or r.activity_power > 500)
  and (r.last_activity_at is not null and r.last_activity_at >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months')
  and not (r.questions_total = 0 and r.answers_total = 0 and coalesce(r.comment_count,0) = 0)
order by r.activity_power desc, r.cohort_month desc, r.user_id
limit 500;