-- {"query": "92.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3588} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as website_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as total_post_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
votes_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_events,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  where v.userid is not null
    and v.creationdate >= (select min(creationdate) from recent_users)
  group by v.userid
),
badges_agg as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    max(b.date) as last_badge_date
  from badges b
  where b.date >= (select min(creationdate) from recent_users)
  group by b.userid
),
comments_agg as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
    and c.creationdate >= (select min(creationdate) from recent_users)
  group by c.userid
),
question_quality as (
  select
    q.owneruserid as user_id,
    count(*) as questions_total,
    avg(coalesce(q.score,0)) as avg_q_score,
    percentile_disc(0.9) within group (order by coalesce(q.viewcount,0)) as p90_q_views,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_q_cnt,
    count(*) filter (where q.closeddate is not null) as closed_q_cnt
  from posts q
  where q.posttypeid = 1
    and q.owneruserid is not null
    and q.creationdate >= (select min(creationdate) from recent_users)
  group by q.owneruserid
),
answer_quality as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    avg(coalesce(a.score,0)) as avg_a_score,
    sum(case when exists (
      select 1
      from posts q2
      where q2.id = a.parentid
        and q2.acceptedanswerid = a.id
    ) then 1 else 0 end) as accepted_as_count
  from posts a
  where a.posttypeid = 2
    and a.owneruserid is not null
    and a.creationdate >= (select min(creationdate) from recent_users)
  group by a.owneruserid
),
dup_links as (
  select
    pl.postid as post_id,
    pl.relatedpostid as dup_of_post_id,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
closed_reasons as (
  select
    ph.postid,
    max(ph.creationdate) as last_close_event,
    max(
      case
        when ph.posthistorytypeid = 10 then
          nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
        else null
      end
    ) as last_close_reason_id_text
  from posthistory ph
  where ph.posthistorytypeid in (10,11) -- closed/reopened events
  group by ph.postid
),
tag_extract as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,''))-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select min(creationdate) from recent_users)
),
top_tags as (
  select
    te.tagname,
    count(*) as tag_cnt,
    row_number() over (order by count(*) desc, tagname) as rn
  from tag_extract te
  group by te.tagname
),
user_top_tag as (
  select
    q.owneruserid as user_id,
    te.tagname,
    count(*) as tag_uses,
    row_number() over (partition by q.owneruserid order by count(*) desc, te.tagname) as rn_tag
  from posts q
  join tag_extract te on te.post_id = q.id
  where q.posttypeid = 1
  group by q.owneruserid, te.tagname
),
activity_timeline as (
  select
    u.id as user_id,
    date_trunc('month', p.creationdate) as month_bucket,
    count(*) as posts_in_month,
    sum(coalesce(p.score,0)) as month_score
  from recent_users u
  left join posts p on p.owneruserid = u.id
                    and p.creationdate >= u.creationdate
  group by u.id, date_trunc('month', p.creationdate)
),
activity_rank as (
  select
    at.user_id,
    at.month_bucket,
    posts_in_month,
    month_score,
    rank() over (partition by at.user_id order by posts_in_month desc, month_score desc, month_bucket) as month_rank
  from activity_timeline at
),
user_flags as (
  select
    u.id as user_id,
    (coalesce(ua.a_count,0) > coalesce(ua.q_count,0)) as is_answer_heavy,
    (coalesce(vu.downvotes_cast,0) > coalesce(vu.upvotes_cast,0)) as more_down_than_up,
    (coalesce(qq.closed_q_cnt,0) > 0) as has_closed_questions,
    (coalesce(qq.accepted_q_cnt,0) > 0) as has_accepted_questions,
    (coalesce(aq.accepted_as_count,0) > 0) as has_accepted_answers,
    (coalesce(ba.gold_count,0) > 0) as has_gold
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
  left join votes_agg vu on vu.user_id = u.id
  left join question_quality qq on qq.user_id = u.id
  left join answer_quality aq on aq.user_id = u.id
  left join badges_agg ba on ba.user_id = u.id
),
score_norm as (
  select
    u.id as user_id,
    ua.total_post_score,
    percentile_disc(0.5) within group (order by coalesce(ua.total_post_score,0)) over () as p50_total_score,
    percentile_disc(0.9) within group (order by coalesce(ua.total_post_score,0)) over () as p90_total_score
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
),
final_metrics as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.cohort_month,
    u.website_norm,
    u.rn_newest,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.total_post_score,0) as total_post_score,
    coalesce(ua.total_views,0) as total_views,
    ua.last_post_activity,
    coalesce(vu.upvotes_cast,0) as upvotes_cast,
    coalesce(vu.downvotes_cast,0) as downvotes_cast,
    coalesce(vu.favorites_cast,0) as favorites_cast,
    coalesce(vu.bounty_total,0) as bounty_total,
    coalesce(ba.badge_count,0) as badge_count,
    coalesce(ba.gold_count,0) as gold_count,
    coalesce(ba.silver_count,0) as silver_count,
    coalesce(ba.bronze_count,0) as bronze_count,
    coalesce(ba.tag_badges,0) as tag_badges,
    ba.last_badge_date,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.comment_score,0) as comment_score,
    ca.last_comment_date,
    coalesce(qq.questions_total,0) as questions_total,
    coalesce(qq.avg_q_score,0) as avg_q_score,
    coalesce(qq.p90_q_views,0) as p90_q_views,
    coalesce(qq.accepted_q_cnt,0) as accepted_q_cnt,
    coalesce(qq.closed_q_cnt,0) as closed_q_cnt,
    coalesce(aq.answers_total,0) as answers_total,
    coalesce(aq.avg_a_score,0) as avg_a_score,
    coalesce(aq.accepted_as_count,0) as accepted_as_count,
    ft.tagname as top_user_tag,
    coalesce(ft.tag_uses,0) as top_user_tag_uses,
    af.month_bucket as peak_activity_month,
    af.posts_in_month as peak_posts_in_month,
    af.month_score as peak_month_score,
    f.is_answer_heavy,
    f.more_down_than_up,
    f.has_closed_questions,
    f.has_accepted_questions,
    f.has_accepted_answers,
    f.has_gold,
    sn.p50_total_score,
    sn.p90_total_score,
    case
      when coalesce(ua.total_post_score,0) >= sn.p90_total_score then 'top_10pct'
      when coalesce(ua.total_post_score,0) >= sn.p50_total_score then 'top_50pct'
      else 'bottom_50pct'
    end as score_bracket
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
  left join votes_agg vu on vu.user_id = u.id
  left join badges_agg ba on ba.user_id = u.id
  left join comments_agg ca on ca.user_id = u.id
  left join question_quality qq on qq.user_id = u.id
  left join answer_quality aq on aq.user_id = u.id
  left join lateral (
    select tagname, tag_uses
    from user_top_tag utt
    where utt.user_id = u.id and utt.rn_tag = 1
  ) ft on true
  left join lateral (
    select month_bucket, posts_in_month, month_score
    from activity_rank ar
    where ar.user_id = u.id and ar.month_rank = 1
  ) af on true
  left join user_flags f on f.user_id = u.id
  left join score_norm sn on sn.user_id = u.id
),
post_outliers as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.posttypeid,
    p.score,
    p.viewcount,
    p.title,
    p.creationdate,
    coalesce(dl.dup_of_post_id, 0) as duplicate_of,
    cr.last_close_event,
    nullif(cr.last_close_reason_id_text,'')::int as close_reason_id,
    row_number() over (partition by p.owneruserid order by coalesce(p.viewcount,0) desc nulls last, p.id) as rn_most_viewed,
    row_number() over (partition by p.owneruserid order by coalesce(p.score,0) desc nulls last, p.id) as rn_highest_score
  from posts p
  left join dup_links dl on dl.post_id = p.id
  left join closed_reasons cr on cr.postid = p.id
  where p.owneruserid in (select user_id from final_metrics)
    and p.creationdate >= (select min(creationdate) from recent_users)
),
best_posts as (
  select
    po.user_id,
    max(case when po.rn_most_viewed = 1 then po.post_id end) as most_viewed_post_id,
    max(case when po.rn_most_viewed = 1 then coalesce(po.viewcount,0) end) as most_views,
    max(case when po.rn_highest_score = 1 then po.post_id end) as highest_score_post_id,
    max(case when po.rn_highest_score = 1 then coalesce(po.score,0) end) as highest_score
  from post_outliers po
  group by po.user_id
),
cohort_compare as (
  select
    fm.cohort_month,
    count(*) as users_in_cohort,
    avg(fm.reputation) as avg_rep,
    avg(fm.q_count + fm.a_count) as avg_posts,
    percentile_disc(0.75) within group (order by fm.total_post_score) as p75_total_score
  from final_metrics fm
  group by fm.cohort_month
),
dense_activity as (
  select
    fm.user_id,
    sum(case when fm.q_count + fm.a_count > 0 then 1 else 0 end)
      + sum(case when fm.comment_count > 0 then 1 else 0 end)
      + sum(case when fm.badge_count > 0 then 1 else 0 end) as activity_signals
  from final_metrics fm
  group by fm.user_id
)
select
  fm.user_id,
  fm.displayname,
  fm.reputation,
  fm.cohort_month,
  fm.website_norm,
  fm.q_count,
  fm.a_count,
  fm.total_post_score,
  fm.total_views,
  fm.upvotes_cast,
  fm.downvotes_cast,
  fm.badge_count,
  fm.gold_count,
  fm.silver_count,
  fm.bronze_count,
  fm.comment_count,
  fm.questions_total,
  fm.answers_total,
  fm.accepted_q_cnt,
  fm.accepted_as_count,
  fm.top_user_tag,
  fm.top_user_tag_uses,
  fm.peak_activity_month,
  fm.peak_posts_in_month,
  fm.peak_month_score,
  fm.is_answer_heavy,
  fm.more_down_than_up,
  fm.has_closed_questions,
  fm.has_accepted_questions,
  fm.has_accepted_answers,
  fm.has_gold,
  fm.score_bracket,
  bp.most_viewed_post_id,
  bp.most_views,
  bp.highest_score_post_id,
  bp.highest_score,
  cc.users_in_cohort,
  cc.avg_rep,
  cc.avg_posts,
  cc.p75_total_score,
  da.activity_signals,
  case
    when fm.has_gold then 'elite'
    when fm.accepted_as_count > 0 and fm.avg_a_score > coalesce(fm.avg_q_score,0) then 'answerer'
    when fm.accepted_q_cnt > 0 then 'questioner'
    else 'mixed'
  end as contributor_archetype
from final_metrics fm
left join best_posts bp on bp.user_id = fm.user_id
left join cohort_compare cc on cc.cohort_month = fm.cohort_month
left join dense_activity da on da.user_id = fm.user_id
where coalesce(fm.displayname,'') <> ''
  and (fm.rn_newest <= 1000 or fm.score_bracket in ('top_10pct','top_50pct'))
order by
  fm.score_bracket desc,
  fm.total_post_score desc nulls last,
  fm.reputation desc,
  fm.user_id
limit 500;