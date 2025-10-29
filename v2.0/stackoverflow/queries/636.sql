-- {"query": "636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3521}
with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    p.lastactivitydate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    coalesce(p.answercount, 0) as answercount,
    row_number() over (partition by p.owneruserid order by p.lastactivitydate desc, p.id desc) as rn_owner_recent,
    dense_rank() over (order by date_trunc('month', p.creationdate)) as cohort_rank
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
owner_stats as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.location,
    u.upvotes,
    u.downvotes,
    u.views as profile_views,
    count(case when p.posttypeid = 1 then 1 end) as q_count,
    count(case when p.posttypeid = 2 then 1 end) as a_count,
    sum(p.score) as total_post_score,
    avg(nullif(p.viewcount,0)) as avg_views_nonzero,
    max(p.lastactivitydate) as last_seen_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.views
),
badges_by_class as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
votes_by_type as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 10 then 1 else 0 end) as deletions
  from votes v
  group by v.postid
),
question_tags as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as tag
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and char_length(p.tags) > 2
),
tag_popularity as (
  select
    qt.tag,
    count(*) as tag_q_count,
    count(distinct qt.post_id) filter (where p.score >= 5) as tag_hot_q_count
  from question_tags qt
  join posts p on p.id = qt.post_id
  group by qt.tag
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as orig_post_id,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
closed_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    max(ph.creationdate) as last_close_date,
    count(*) as close_event_count,
    min(nullif(ph.comment,'')) as first_close_reason_text
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
owner_recent_posts as (
  select ra.*
  from recent_activity ra
  where ra.rn_owner_recent <= 5
),
activity_rollup as (
  select
    ra.owneruserid as user_id,
    count(*) as recent_post_count,
    sum(ra.score) as recent_score_sum,
    sum(coalesce(vt.upvotes,0)) as recent_upvotes,
    sum(coalesce(vt.downvotes,0)) as recent_downvotes,
    max(ra.lastactivitydate) as latest_recent_activity,
    avg(ra.viewcount) as avg_recent_views
  from owner_recent_posts ra
  left join votes_by_type vt on vt.postid = ra.post_id
  group by ra.owneruserid
),
answer_accepts as (
  select
    a.id as answer_id,
    a.owneruserid as answerer_id,
    q.id as question_id,
    case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
  from posts a
  join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
),
accept_stats as (
  select
    answerer_id as user_id,
    count(*) as total_answers,
    sum(is_accepted) as accepted_answers,
    round(100.0 * nullif(sum(is_accepted),0) / nullif(count(*),0), 2) as accept_rate_pct
  from answer_accepts
  group by answerer_id
),
commenter_activity as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
hot_questions as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    row_number() over (partition by date_trunc('month', p.creationdate) order by p.score desc, p.viewcount desc, p.id) as rn_monthly_hot
  from posts p
  where p.posttypeid = 1
),
user_monthly_hot as (
  select
    user_id,
    count(case when rn_monthly_hot <= 10 then 1 end) as top10_month_hits
  from hot_questions
  group by user_id
),
cohorts as (
  select
    u.id as user_id,
    date_trunc('year', u.creationdate) as cohort_year
  from users u
),
null_edge_cases as (
  select
    p.id as post_id,
    case
      when p.owneruserid is null and coalesce(p.ownerdisplayname, '') = '' then 'anonymous'
      when p.owneruserid is null then 'named_anonymous'
      else 'registered'
    end as author_kind
  from posts p
),
final_users as (
  select
    os.user_id,
    os.displayname,
    os.reputation,
    os.location,
    os.q_count,
    os.a_count,
    os.total_post_score,
    os.last_seen_post_activity,
    coalesce(bc.gold,0) as gold_badges,
    coalesce(bc.silver,0) as silver_badges,
    coalesce(bc.bronze,0) as bronze_badges,
    bc.first_badge_date,
    bc.last_badge_date,
    coalesce(ar.recent_post_count,0) as recent_post_count,
    coalesce(ar.recent_score_sum,0) as recent_score_sum,
    coalesce(ar.recent_upvotes,0) as recent_upvotes,
    coalesce(ar.recent_downvotes,0) as recent_downvotes,
    ar.latest_recent_activity,
    ar.avg_recent_views,
    coalesce(as2.total_answers,0) as total_answers,
    coalesce(as2.accepted_answers,0) as accepted_answers,
    coalesce(as2.accept_rate_pct,0) as accept_rate_pct,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.pos_comment_count,0) as pos_comment_count,
    ca.last_comment_date,
    coalesce(umh.top10_month_hits,0) as monthly_top10_hot_q_hits,
    c.cohort_year
  from owner_stats os
  left join badges_by_class bc on bc.userid = os.user_id
  left join activity_rollup ar on ar.user_id = os.user_id
  left join accept_stats as2 on as2.user_id = os.user_id
  left join commenter_activity ca on ca.user_id = os.user_id
  left join user_monthly_hot umh on umh.user_id = os.user_id
  left join cohorts c on c.user_id = os.user_id
),
question_quality as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.score,
    q.viewcount,
    q.favoritecount,
    coalesce(vt.upvotes,0) as upvotes,
    coalesce(vt.downvotes,0) as downvotes,
    (coalesce(vt.upvotes,0) - coalesce(vt.downvotes,0)) as net_votes,
    ln(1 + greatest(q.viewcount,0)) as ln_views,
    (coalesce(vt.upvotes,0) - coalesce(vt.downvotes,0)) * ln(1 + greatest(q.viewcount,0)) as quality_index,
    ce.first_close_date,
    ce.first_close_reason_text,
    dl.orig_post_id as duplicate_of
  from posts q
  left join votes_by_type vt on vt.postid = q.id
  left join closed_events ce on ce.postid = q.id
  left join dup_links dl on dl.dup_post_id = q.id
  where q.posttypeid = 1
),
top_tags_per_user as (
  select
    qt.tag,
    q.owneruserid as user_id,
    count(*) as tag_uses,
    row_number() over (partition by q.owneruserid order by count(*) desc, qt.tag) as rn
  from question_tags qt
  join posts q on q.id = qt.post_id
  group by qt.tag, q.owneruserid
),
user_top_tag as (
  select user_id, tag as top_tag, tag_uses
  from top_tags_per_user
  where rn = 1
),
union_space as (
  select post_id, posttypeid, owneruserid, score, viewcount, title, tags
  from owner_recent_posts
  union all
  select q.question_id as post_id, 1 as posttypeid, q.user_id as owneruserid, q.score, q.viewcount, null as title, null as tags
  from question_quality q
  where q.quality_index > 0
  union
  select p.id, p.posttypeid, p.owneruserid, p.score, p.viewcount, p.title, p.tags
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    and (p.score > 10 or (p.viewcount > 1000 and coalesce(p.answercount,0) >= 2))
),
post_rankings as (
  select
    us.post_id,
    us.posttypeid,
    us.owneruserid,
    us.score,
    us.viewcount,
    sum(us.score) over (partition by us.owneruserid) as score_by_owner,
    rank() over (order by us.score desc, us.viewcount desc, us.post_id desc) as global_score_rank,
    row_number() over (partition by us.owneruserid order by us.score desc, us.viewcount desc, us.post_id desc) as owner_best_row
  from union_space us
),
filtered_posts as (
  select pr.post_id, pr.posttypeid, pr.owneruserid, pr.score, pr.viewcount, pr.score_by_owner, pr.global_score_rank, pr.owner_best_row
  from post_rankings pr
  where
    (pr.score >= 0 or pr.viewcount is not null)
    and not (pr.score is null and pr.viewcount is null)
    and (pr.posttypeid in (1,2) or pr.posttypeid not in (3,4,5))
),
final as (
  select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.location,
    fu.q_count,
    fu.a_count,
    fu.total_post_score,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.accept_rate_pct,
    fu.comment_count,
    fu.monthly_top10_hot_q_hits,
    fu.cohort_year,
    utt.top_tag,
    tp.tag_q_count,
    tp.tag_hot_q_count,
    sum(case when fp.posttypeid = 1 then 1 else 0 end) as joined_questions,
    sum(case when fp.posttypeid = 2 then 1 else 0 end) as joined_answers,
    max(fp.score_by_owner) as score_by_owner_max,
    min(fp.global_score_rank) as best_global_rank,
    min(case when fp.owner_best_row = 1 then fp.post_id end) as best_post_id
  from final_users fu
  left join user_top_tag utt on utt.user_id = fu.user_id
  left join tag_popularity tp on tp.tag = utt.top_tag
  left join filtered_posts fp on fp.owneruserid = fu.user_id
  group by
    fu.user_id, fu.displayname, fu.reputation, fu.location, fu.q_count, fu.a_count, fu.total_post_score,
    fu.gold_badges, fu.silver_badges, fu.bronze_badges, fu.accept_rate_pct, fu.comment_count,
    fu.monthly_top10_hot_q_hits, fu.cohort_year, utt.top_tag, tp.tag_q_count, tp.tag_hot_q_count
)
select
  f.user_id,
  f.displayname,
  f.reputation,
  f.location,
  f.cohort_year,
  f.q_count,
  f.a_count,
  f.total_post_score,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.accept_rate_pct,
  f.comment_count,
  f.monthly_top10_hot_q_hits,
  coalesce(f.top_tag, '(none)') as top_tag,
  coalesce(f.tag_q_count, 0) as top_tag_qs,
  coalesce(f.tag_hot_q_count, 0) as top_tag_hot_qs,
  f.joined_questions,
  f.joined_answers,
  f.score_by_owner_max,
  f.best_global_rank,
  f.best_post_id,
  case
    when f.reputation >= 100000 then 'legend'
    when f.reputation >= 25000 and f.gold_badges >= 10 then 'elite'
    when f.reputation >= 10000 and (f.gold_badges + f.silver_badges) >= 20 then 'expert'
    when f.reputation >= 2000 and (f.a_count > f.q_count or f.accept_rate_pct >= 50) then 'proficient'
    when f.q_count + f.a_count >= 10 then 'active'
    else 'newbie'
  end as user_tier,
  (
    select min(q.creationdate) - min(a.creationdate)
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.owneruserid = f.user_id
      and q.posttypeid = 1
  ) as min_time_to_first_accept,
  exists (
    select 1
    from posts px
    where px.owneruserid = f.user_id
      and px.posttypeid = 1
      and px.closeddate is not null
  ) as has_closed_questions,
  trim(both ' ' from coalesce(f.displayname, '[unknown]')) || ' (#' || cast(f.user_id as text) || ')' as display_handle
from final f
where
  (coalesce(f.q_count,0) + coalesce(f.a_count,0) >= 5 or f.reputation >= 5000)
  and not (f.gold_badges is null and f.silver_badges is null and f.bronze_badges is null)
  and (
    f.top_tag is null
    or f.tag_q_count >= greatest(5, coalesce(f.tag_hot_q_count,0))
  )
order by
  user_tier desc,
  f.reputation desc,
  f.score_by_owner_max desc nulls last,
  f.best_global_rank asc nulls last
limit 250;