-- {"query": "742.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2988}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_cnt,
    count(*) filter (where p.posttypeid = 2) as a_cnt,
    sum(p.score) as post_score_sum,
    sum(coalesce(p.viewcount, 0)) as post_views_sum,
    max(p.lastactivitydate) as last_post_activity,
    count(*) filter (where p.closeddate is not null) as closed_posts
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
votes_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upmods_cast,
    count(*) filter (where v.votetypeid = 3) as downmods_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_involved,
    sum(coalesce(v.bountyamount,0) * case when v.votetypeid in (8,9) then 1 else 0 end) as bounty_amount_sum
  from votes v
  group by v.userid
),
badges_agg as (
  select
    b.userid as user_id,
    count(*) as badge_cnt,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = true) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
comments_agg as (
  select
    c.userid as user_id,
    count(*) as comment_cnt,
    sum(coalesce(c.score,0)) as comment_score_sum,
    max(c.creationdate) as last_comment_date
  from comments c
  group by c.userid
),
question_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) filter (where p.posttypeid = 1) as avg_q_score,
    avg(p.viewcount) filter (where p.posttypeid = 1 and p.viewcount is not null) as avg_q_views,
    percentile_cont(0.9) within group (order by p.viewcount) filter (where p.posttypeid = 1 and p.viewcount is not null) as p90_q_views,
    sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_qs
  from posts p
  group by p.owneruserid
),
answer_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) filter (where p.posttypeid = 2) as avg_a_score,
    sum(case when exists (
      select 1
      from posts q
      where q.id = p.parentid
        and q.acceptedanswerid = p.id
    ) then 1 else 0 end) as accepted_as
  from posts p
  group by p.owneruserid
),
tag_extraction as (
  select
    q.owneruserid as user_id,
    lower(unnest(string_to_array(substring(q.tags from 2 for length(q.tags)-2), '><'))) as tag
  from posts q
  where q.posttypeid = 1
    and q.tags is not null
),
top_tags as (
  select
    user_id,
    string_agg(tag || ':' || cast(cnt as varchar), ', ' order by cnt desc, tag asc) as top_tags_kv,
    max(cnt) as top_tag_count
  from (
    select user_id, tag, count(*) as cnt,
           row_number() over (partition by user_id order by count(*) desc, tag asc) as rn
    from tag_extraction
    group by user_id, tag
  ) t
  where rn <= 5
  group by user_id
),
link_network as (
  select
    u.id as user_id,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_links_out,
    count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as linked_posts_out,
    count(distinct case when pl.linktypeid = 3 then pl.postid end) as dup_links_in_candidates
  from users u
  left join posts p on p.owneruserid = u.id
  left join postlinks pl on pl.postid = p.id
  group by u.id
),
edits_and_closes as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_count,
    count(*) filter (where ph.posthistorytypeid = 10) as closes_count,
    count(*) filter (where ph.posthistorytypeid = 11) as reopens_count,
    count(*) filter (where ph.posthistorytypeid in (35,36)) as migrations_count,
    max(ph.creationdate) as last_history_date,
    count(*) filter (where ph.posthistorytypeid = 10 and (ph.comment ~ '^[0-9]+$') and cast(ph.comment as integer) in (101,102,103,104,105)) as modern_closes
  from posthistory ph
  group by ph.userid
),
user_post_temporal as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as post_month,
    count(*) as posts_in_month,
    avg(p.score) as avg_score_in_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_trend as (
  select
    user_id,
    post_month,
    posts_in_month,
    avg_score_in_month,
    sum(posts_in_month) over (partition by user_id order by post_month rows between 11 preceding and current row) as rolling_12m_posts,
    avg(avg_score_in_month) over (partition by user_id order by post_month rows between 5 preceding and current row) as rolling_6m_avg_score
  from user_post_temporal
),
ranked_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ua.q_cnt,
    ua.a_cnt,
    ua.post_score_sum,
    ua.post_views_sum,
    ua.closed_posts,
    va.upmods_cast,
    va.downmods_cast,
    va.favorites_cast,
    va.bounties_involved,
    va.bounty_amount_sum,
    ba.badge_cnt,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    ba.tag_badges,
    ca.comment_cnt,
    ca.comment_score_sum,
    qq.avg_q_score,
    qq.avg_q_views,
    qq.p90_q_views,
    qq.accepted_qs,
    aq.avg_a_score,
    aq.accepted_as,
    tt.top_tags_kv,
    ln.dup_links_out,
    ln.linked_posts_out,
    ea.edits_count,
    ea.closes_count,
    ea.reopens_count,
    ea.migrations_count,
    greatest(coalesce(ua.last_post_activity, timestamp '1970-01-01'),
             coalesce(ca.last_comment_date, timestamp '1970-01-01'),
             coalesce(ba.last_badge_date, timestamp '1970-01-01'),
             coalesce(ea.last_history_date, timestamp '1970-01-01')) as last_seen_activity,
    coalesce(at.rolling_12m_posts, 0) as rolling_12m_posts,
    coalesce(at.rolling_6m_avg_score, 0) as rolling_6m_avg_score,
    dense_rank() over (order by coalesce(ua.post_score_sum,0) + coalesce(ca.comment_score_sum,0) + coalesce(ba.badge_cnt,0) desc) as score_rank,
    row_number() over (order by coalesce(ua.post_views_sum,0) desc, coalesce(ua.post_score_sum,0) desc) as views_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join votes_agg va on va.user_id = ru.user_id
  left join badges_agg ba on ba.user_id = ru.user_id
  left join comments_agg ca on ca.user_id = ru.user_id
  left join question_quality qq on qq.user_id = ru.user_id
  left join answer_quality aq on aq.user_id = ru.user_id
  left join top_tags tt on tt.user_id = ru.user_id
  left join link_network ln on ln.user_id = ru.user_id
  left join edits_and_closes ea on ea.user_id = ru.user_id
  left join lateral (
    select at1.rolling_12m_posts, at1.rolling_6m_avg_score, at1.post_month
    from activity_trend at1
    where at1.user_id = ru.user_id
    order by at1.post_month desc
    limit 1
  ) at on true
),
question_duplicates as (
  select
    q.owneruserid as user_id,
    count(distinct q.id) as dup_marked_questions
  from posts q
  left join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
  where q.posttypeid = 1
    and pl.relatedpostid is not null
  group by q.owneruserid
),
saves_removed_proxy as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 5) as legacy_favorites
  from votes v
  group by v.userid
),
final_scores as (
  select
    r.*,
    coalesce(qd.dup_marked_questions, 0) as dup_marked_questions,
    coalesce(sr.legacy_favorites, 0) as legacy_favorites,
    case
      when coalesce(ua.a_cnt,0) + coalesce(ua.q_cnt,0) = 0 then null
      else round(coalesce(aq.accepted_as,0) / nullif(coalesce(ua.a_cnt,0),0), 4)
    end as answer_accept_rate,
    case when r.downmods_cast is null or r.downmods_cast = 0 then null else coalesce(r.upmods_cast,0) / nullif(r.downmods_cast,0) end as up_down_ratio,
    case when r.gold_badges > 0 then 'Gold'
         when r.silver_badges > 0 then 'Silver'
         when r.bronze_badges > 0 then 'Bronze'
         else 'None' end as highest_badge_tier
  from ranked_users r
  left join user_activity ua on ua.user_id = r.user_id
  left join answer_quality aq on aq.user_id = r.user_id
  left join question_duplicates qd on qd.user_id = r.user_id
  left join saves_removed_proxy sr on sr.user_id = r.user_id
)
select
  fs.user_id,
  fs.displayname,
  fs.reputation,
  fs.cohort_month,
  fs.q_cnt,
  fs.a_cnt,
  fs.post_score_sum,
  fs.post_views_sum,
  fs.comment_cnt,
  fs.badge_cnt,
  fs.gold_badges,
  fs.silver_badges,
  fs.bronze_badges,
  fs.tag_badges,
  fs.avg_q_score,
  fs.avg_a_score,
  fs.avg_q_views,
  fs.p90_q_views,
  fs.accepted_qs,
  fs.accepted_as,
  fs.dup_links_out,
  fs.linked_posts_out,
  fs.edits_count,
  fs.closes_count,
  fs.reopens_count,
  fs.migrations_count,
  fs.dup_marked_questions,
  fs.legacy_favorites,
  fs.top_tags_kv,
  fs.last_seen_activity,
  fs.rolling_12m_posts,
  fs.rolling_6m_avg_score,
  fs.answer_accept_rate,
  fs.up_down_ratio,
  fs.highest_badge_tier,
  fs.score_rank,
  fs.views_rank,
  case
    when fs.reputation >= 100000 then 'Legend'
    when fs.reputation >= 50000 then 'Elite'
    when fs.reputation >= 10000 then 'Advanced'
    when fs.reputation >= 1000 then 'Intermediate'
    else 'Newbie'
  end as reputation_band
from final_scores fs
where coalesce(fs.post_score_sum,0) + coalesce(fs.comment_score_sum,0) + coalesce(fs.badge_cnt,0) > (
  select percentile_cont(0.75) within group (order by coalesce(ua.post_score_sum,0) + coalesce(ca.comment_score_sum,0) + coalesce(ba.badge_cnt,0))
  from users u0
  left join user_activity ua on ua.user_id = u0.id
  left join comments_agg ca on ca.user_id = u0.id
  left join badges_agg ba on ba.user_id = u0.id
)
order by fs.score_rank, fs.views_rank
limit 200;