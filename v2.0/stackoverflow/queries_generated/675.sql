-- {"query": "675.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3607} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_array
  from posts p
  where p.posttypeid = 1
),
user_activity as (
  select
    u.user_id,
    count(distinct q.id) filter (where q.id is not null) as questions_count,
    count(distinct a.id) filter (where a.id is not null) as answers_count,
    sum(coalesce(q.score, 0)) as total_q_score,
    sum(coalesce(a.score, 0)) as total_a_score,
    sum(coalesce(q.viewcount, 0)) as total_q_views,
    count(distinct c.id) as comments_count,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_cast
  from recent_users u
  left join posts q on q.posttypeid = 1 and q.owneruserid = u.user_id
  left join posts a on a.posttypeid = 2 and a.owneruserid = u.user_id
  left join comments c on c.userid = u.user_id
  left join votes v on v.userid = u.user_id
  group by u.user_id
),
accepted_answer_ratio as (
  select
    a.owneruserid as user_id,
    count(*) filter (where q.acceptedanswerid = a.id) as accepted_answers,
    count(*) as total_answers_by_user,
    avg(case when q.acceptedanswerid = a.id then 1.0 else 0.0 end) as accept_ratio
  from posts a
  join posts q on q.posttypeid = 1 and q.id = a.parentid
  where a.posttypeid = 2
  group by a.owneruserid
),
tag_pref as (
  select
    q.owneruserid as user_id,
    lower(unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))) as tagname,
    count(*) as tag_uses,
    sum(q.score) as tag_score_sum
  from posts q
  where q.posttypeid = 1
    and q.tags is not null
    and length(q.tags) > 2
  group by q.owneruserid, lower(unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')))
),
top_tag_per_user as (
  select user_id, tagname, tag_uses, tag_score_sum, rn
  from (
    select
      t.user_id,
      t.tagname,
      t.tag_uses,
      t.tag_score_sum,
      row_number() over (partition by t.user_id order by t.tag_uses desc, t.tag_score_sum desc, t.tagname) as rn
    from tag_pref t
  ) s
  where rn = 1
),
badges_rollup as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
post_link_stats as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_mark_count
  from posts p
  left join postlinks pl on pl.postid = p.id
  group by p.owneruserid
),
comment_sentiment as (
  select
    c.userid as user_id,
    avg(nullif(length(c.text), 0)) as avg_comment_length,
    sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count,
    sum(case when position('helpful' in lower(c.text)) > 0 then 1 else 0 end) as helpful_count
  from comments c
  group by c.userid
),
close_events as (
  select
    ph.userid as user_id,
    count(*) as close_events_count,
    count(*) filter (where ph.comment in ('101','1')) as duplicate_closes
  from posthistory ph
  where ph.posthistorytypeid in (10,11,12,13,14,15)
  group by ph.userid
),
vote_impact as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_received,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received
  from votes v
  join posts p on p.id = v.postid
  group by p.owneruserid
),
hotness as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.creationdate,
    coalesce(q.viewcount,0)*0.001
      + coalesce(q.score,0)*1.5
      + coalesce(q.favoritecount,0)*0.75
      + coalesce(q.answercount,0)*0.5
      - extract(epoch from (now() - coalesce(q.lastactivitydate, q.creationdate))) / 86400 * 0.05
      as hot_score
  from posts q
  where q.posttypeid = 1
),
user_hotness as (
  select
    h.user_id,
    avg(h.hot_score) as avg_hot_score,
    max(h.hot_score) as max_hot_score,
    count(*) filter (where h.hot_score > 5) as hot_questions_5plus
  from hotness h
  group by h.user_id
),
activity_timeline as (
  select
    u.user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) filter (where p.posttypeid = 1) as q_month,
    count(*) filter (where p.posttypeid = 2) as a_month,
    count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_month
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  group by u.user_id, date_trunc('month', p.creationdate)
),
activity_trend as (
  select
    user_id,
    sum(q_month + a_month + other_month) as total_posts_window,
    stddev_pop(q_month + a_month + other_month) as post_volatility,
    corr(extract(epoch from month), (q_month + a_month + other_month)::float) as time_corr
  from activity_timeline
  group by user_id
),
q_quality as (
  select
    q.owneruserid as user_id,
    percentile_cont(0.5) within group (order by coalesce(q.score,0)) as median_q_score,
    avg(coalesce(q.viewcount,0)) as avg_q_views,
    avg(coalesce(q.commentcount,0)) as avg_q_comments
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
a_quality as (
  select
    a.owneruserid as user_id,
    avg(coalesce(a.score,0)) as avg_a_score,
    count(*) filter (where a.score >= 5) as answers_5plus
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
user_rank as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    ua.questions_count,
    ua.answers_count,
    ua.total_q_score,
    ua.total_a_score,
    ua.total_q_views,
    ua.comments_count,
    ua.net_votes_cast,
    coalesce(vr.net_votes_received,0) as net_votes_received,
    coalesce(vr.upvotes_received,0) as upvotes_received,
    coalesce(vr.downvotes_received,0) as downvotes_received,
    coalesce(ar.accepted_answers,0) as accepted_answers,
    coalesce(ar.total_answers_by_user,0) as total_answers_by_user,
    coalesce(ar.accept_ratio,0) as accept_ratio,
    coalesce(br.badges_total,0) as badges_total,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    br.first_badge_date,
    br.last_badge_date,
    coalesce(pl.linked_count,0) as linked_count,
    coalesce(pl.duplicate_mark_count,0) as duplicate_mark_count,
    coalesce(cs.avg_comment_length,0) as avg_comment_length,
    coalesce(cs.thanks_count,0) as thanks_count,
    coalesce(cs.helpful_count,0) as helpful_count,
    coalesce(uh.avg_hot_score,0) as avg_hot_score,
    coalesce(uh.max_hot_score,0) as max_hot_score,
    coalesce(uh.hot_questions_5plus,0) as hot_questions_5plus,
    coalesce(at.total_posts_window,0) as total_posts_window,
    coalesce(at.post_volatility,0) as post_volatility,
    coalesce(at.time_corr,0) as time_corr,
    coalesce(qq.median_q_score,0) as median_q_score,
    coalesce(qq.avg_q_views,0) as avg_q_views,
    coalesce(qq.avg_q_comments,0) as avg_q_comments,
    coalesce(aq.avg_a_score,0) as avg_a_score,
    coalesce(aq.answers_5plus,0) as answers_5plus,
    coalesce(tt.tagname, 'none') as top_tag,
    coalesce(tt.tag_uses,0) as top_tag_uses,
    coalesce(tt.tag_score_sum,0) as top_tag_score_sum
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join accepted_answer_ratio ar on ar.user_id = u.user_id
  left join badges_rollup br on br.user_id = u.user_id
  left join post_link_stats pl on pl.user_id = u.user_id
  left join comment_sentiment cs on cs.user_id = u.user_id
  left join vote_impact vr on vr.user_id = u.user_id
  left join user_hotness uh on uh.user_id = u.user_id
  left join activity_trend at on at.user_id = u.user_id
  left join q_quality qq on qq.user_id = u.user_id
  left join a_quality aq on aq.user_id = u.user_id
  left join top_tag_per_user tt on tt.user_id = u.user_id
),
score_components as (
  select
    ur.*,
    -- normalize components with log/scale to avoid dominance; add small epsilon to avoid ln(0)
    ln(1 + greatest(ur.reputation,0)) * 0.8
      + ln(1 + greatest(ur.questions_count,0)) * 0.5
      + ln(1 + greatest(ur.answers_count,0)) * 1.1
      + ln(1 + greatest(ur.total_q_views,0)) * 0.3
      + ln(1 + greatest(ur.total_q_score + ur.total_a_score + ur.net_votes_received,0)) * 1.2
      + ln(1 + greatest(ur.badges_total + ur.gold_badges*2 + ur.silver_badges,0)) * 0.6
      + ln(1 + greatest(ur.accepted_answers,0)) * 0.9
      + greatest(ur.avg_hot_score,0) * 0.4
      + greatest(ur.max_hot_score,0) * 0.2
      + greatest(ur.answers_5plus,0) * 0.3
      + case when ur.time_corr > 0 then ur.time_corr else 0 end * 2.0
      - greatest(ur.downvotes_received - ur.upvotes_received, 0) * 0.05
      - case when ur.post_volatility > 5 then 0.2 else 0 end
      as composite_score_raw
  from user_rank ur
),
ranked as (
  select
    sc.*,
    dense_rank() over (order by sc.composite_score_raw desc, sc.user_id) as dense_rank_overall,
    percent_rank() over (order by sc.composite_score_raw) as percentile_low_to_high,
    ntile(20) over (order by sc.composite_score_raw desc) as vigintile
  from score_components sc
),
dupe_clusters as (
  select
    q.owneruserid as user_id,
    count(distinct pl.relatedpostid) as distinct_duplicate_targets
  from posts q
  join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
  group by q.owneruserid
),
finalized as (
  select
    r.*,
    coalesce(dc.distinct_duplicate_targets,0) as distinct_duplicate_targets,
    case
      when r.top_tag in ('sql','postgresql','mysql','tsql') then 'Data'
      when r.top_tag in ('javascript','java','python','c#','c++') then 'Code'
      when r.top_tag = 'none' then 'None'
      else 'Other'
    end as top_tag_family
  from ranked r
  left join dupe_clusters dc on dc.user_id = r.user_id
)
select
  f.user_id,
  coalesce(nullif(f.displayname,''), concat('user#', f.user_id::varchar)) as displayname,
  f.location,
  f.websiteurl,
  f.reputation,
  f.questions_count,
  f.answers_count,
  f.accepted_answers,
  f.accept_ratio,
  f.badges_total,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.total_q_views,
  f.total_q_score,
  f.total_a_score,
  f.net_votes_received,
  f.upvotes_received,
  f.downvotes_received,
  f.comments_count,
  f.linked_count,
  f.duplicate_mark_count,
  f.distinct_duplicate_targets,
  f.avg_comment_length,
  f.thanks_count,
  f.helpful_count,
  f.avg_hot_score,
  f.max_hot_score,
  f.hot_questions_5plus,
  f.total_posts_window,
  f.post_volatility,
  f.time_corr,
  f.median_q_score,
  f.avg_q_views,
  f.avg_q_comments,
  f.avg_a_score,
  f.answers_5plus,
  f.top_tag,
  f.top_tag_family,
  f.top_tag_uses,
  f.top_tag_score_sum,
  round(f.composite_score_raw::numeric, 4) as composite_score,
  f.dense_rank_overall,
  f.percentile_low_to_high,
  f.vigintile,
  case
    when f.vigintile <= 2 then 'S'
    when f.vigintile <= 5 then 'A'
    when f.vigintile <= 10 then 'B'
    when f.vigintile <= 15 then 'C'
    else 'D'
  end as grade_band
from finalized f
where
  (f.answers_count > 0 or f.questions_count > 0)
  and (f.creationdate <= now() and f.creationdate is not null)
  and (f.reputation is not null and f.reputation >= 1)
order by f.composite_score_raw desc, f.user_id
limit 200;