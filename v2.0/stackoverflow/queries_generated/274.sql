-- {"query": "274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2861} 
with
-- recent active users with mixed metrics
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    u.upvotes,
    u.downvotes,
    u.views,
    (u.upvotes - u.downvotes) as net_votes,
    row_number() over (order by u.lastaccessdate desc, u.id) as rn_recent
  from users u
  where u.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '3 years' from posts p)
),
-- questions and answers with tag extraction and quality proxy
qa as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.acceptedanswerid,
    p.parentid,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer,
    coalesce(p.viewcount,0) + 50 * coalesce(p.favoritecount,0) + 10 * coalesce(p.answercount,0) + 5 * coalesce(p.commentcount,0) + 25 * greatest(coalesce(p.score,0),0) as quality_score,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_array
  from posts p
  where p.posttypeid in (1,2)
),
-- explode tags for questions only
q_tags as (
  select
    q.id as question_id,
    lower(t) as tag
  from qa q
  cross join lateral unnest(case when q.is_question = 1 then q.tag_array else array[]::varchar[] end) as t
),
-- compute per-user aggregates with window functions
user_activity as (
  select
    u.user_id,
    count(*) filter (where q.is_question = 1) as questions,
    count(*) filter (where q.is_answer = 1) as answers,
    sum(q.quality_score) as total_quality,
    avg(q.quality_score) filter (where q.is_question = 1) as avg_q_quality,
    avg(q.quality_score) filter (where q.is_answer = 1) as avg_a_quality,
    max(q.score) as best_score,
    min(q.score) as worst_score,
    sum(case when q.is_answer = 1 and q.score > 0 then 1 else 0 end) as pos_answers,
    sum(case when q.is_question = 1 and q.acceptedanswerid is not null then 1 else 0 end) as questions_with_accept,
    percentile_cont(0.5) within group (order by q.score) as median_post_score
  from recent_users u
  left join qa q on q.owneruserid = u.user_id
  group by u.user_id
),
-- tag popularity for user questions vs global
tag_stats as (
  select
    ru.user_id,
    qt.tag,
    count(*) as user_tag_q_count,
    sum(count(*)) over (partition by qt.tag) as global_tag_q_count,
    row_number() over (partition by ru.user_id order by count(*) desc, qt.tag) as rn_user_tag
  from recent_users ru
  join qa q on q.owneruserid = ru.user_id and q.is_question = 1
  join q_tags qt on qt.question_id = q.id
  group by ru.user_id, qt.tag
),
-- recent duplicate/linked interactions
link_activity as (
  select
    ru.user_id,
    count(*) filter (where pl.linktypeid = 3) as dup_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_date
  from recent_users ru
  left join posts p on p.owneruserid = ru.user_id
  left join postlinks pl on pl.postid = p.id
  group by ru.user_id
),
-- comment sentiment proxy using string ops and regex-like counts
comment_metrics as (
  select
    ru.user_id,
    count(c.id) as comments_made,
    sum(c.score) as comment_score_sum,
    avg(c.score) as comment_score_avg,
    sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_mentions,
    sum(case when position('?'' in c.text) > 0 or position('?' in c.text) > 0 then 1 else 0 end) as question_comments,
    max(c.creationdate) as last_comment_date
  from recent_users ru
  left join comments c on c.userid = ru.user_id
  group by ru.user_id
),
-- badge mix
badge_mix as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
-- detect post closures and reasons for user's questions
closure_info as (
  select
    q.owneruserid as user_id,
    count(distinct q.id) as closed_questions,
    count(*) filter (where ph.comment::int = 101) as duplicate_closures,
    count(*) filter (where ph.comment::int = 102) as offtopic_closures,
    max(ph.creationdate) as last_close_date
  from qa q
  join posthistory ph
    on ph.postid = q.id
   and ph.posthistorytypeid = 10
  where q.is_question = 1
  group by q.owneruserid
),
-- voting behavior: up/down on others' posts
voting_behavior as (
  select
    ru.user_id,
    count(*) filter (where v.votetypeid = 2) as upmods_cast,
    count(*) filter (where v.votetypeid = 3) as downmods_cast,
    count(distinct v.postid) filter (where v.votetypeid in (2,3)) as distinct_voted_posts,
    max(v.creationdate) as last_vote_date
  from recent_users ru
  left join votes v on v.userid = ru.user_id
  group by ru.user_id
),
-- recency buckets using window and gaps
activity_recency as (
  select
    ru.user_id,
    greatest(
      coalesce(extract(epoch from (current_timestamp - ru.lastaccessdate))::bigint, 0),
      0
    ) as seconds_since_last_access,
    greatest(
      coalesce(extract(epoch from (current_timestamp - ua.most_recent_post))::bigint, 9223372036854775807)
    ) as seconds_since_last_post
  from recent_users ru
  left join (
    select owneruserid, max(creationdate) as most_recent_post
    from posts
    group by owneruserid
  ) ua on ua.owneruserid = ru.user_id
),
-- per-user rolling rank by composite score
user_composite as (
  select
    ru.user_id,
    ru.displayname,
    ru.location_norm,
    ru.reputation,
    ru.net_votes,
    coalesce(ua.total_quality,0) as total_quality,
    coalesce(ua.avg_q_quality,0) as avg_q_quality,
    coalesce(ua.avg_a_quality,0) as avg_a_quality,
    coalesce(ua.questions,0) as q_count,
    coalesce(ua.answers,0) as a_count,
    coalesce(ua.median_post_score,0) as median_post_score,
    coalesce(lk.dup_links,0) as dup_links,
    coalesce(lk.related_links,0) as related_links,
    coalesce(cm.comments_made,0) as comments_made,
    coalesce(cm.comment_score_sum,0) as comment_score_sum,
    coalesce(cm.thanks_mentions,0) as thanks_mentions,
    coalesce(bm.badges_total,0) as badges_total,
    coalesce(bm.gold_badges,0) as gold_badges,
    coalesce(bm.silver_badges,0) as silver_badges,
    coalesce(bm.bronze_badges,0) as bronze_badges,
    coalesce(cl.closed_questions,0) as closed_questions,
    coalesce(vb.upmods_cast,0) as upmods_cast,
    coalesce(vb.downmods_cast,0) as downmods_cast,
    ar.seconds_since_last_access,
    ar.seconds_since_last_post,
    -- composite score
    ( 0.002 * ru.reputation
    + 0.05  * coalesce(ua.total_quality,0)
    + 3.0   * coalesce(ua.questions_with_accept,0)
    + 1.5   * coalesce(ua.pos_answers,0)
    + 2.0   * coalesce(bm.gold_badges,0)
    + 1.0   * coalesce(bm.silver_badges,0)
    + 0.5   * coalesce(bm.bronze_badges,0)
    - 0.5   * coalesce(cl.closed_questions,0)
    - 1.0   * greatest(coalesce(vb.downmods_cast,0) - coalesce(vb.upmods_cast,0), 0)
    ) as composite_score
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join link_activity lk on lk.user_id = ru.user_id
  left join comment_metrics cm on cm.user_id = ru.user_id
  left join badge_mix bm on bm.user_id = ru.user_id
  left join closure_info cl on cl.user_id = ru.user_id
  left join voting_behavior vb on vb.user_id = ru.user_id
  left join activity_recency ar on ar.user_id = ru.user_id
),
-- pick each user's top tag (by their own question count) with tiebreakers using global popularity
top_tag as (
  select
    ts.user_id,
    ts.tag as top_tag,
    ts.user_tag_q_count,
    ts.global_tag_q_count
  from tag_stats ts
  where ts.rn_user_tag = 1
),
-- correlated subquery: accepted answer age vs question age
answer_latency as (
  select
    q.owneruserid as user_id,
    avg(extract(epoch from (a.creationdate - q.creationdate))/3600.0) as avg_hours_to_accept
  from qa q
  join posts a on a.id = q.acceptedanswerid
  where q.is_question = 1
  group by q.owneruserid
),
-- percentile ranks
ranked as (
  select
    uc.*,
    ntile(100) over (order by composite_score desc nulls last) as composite_percentile,
    dense_rank() over (order by composite_score desc, user_id) as dense_rank_overall
  from user_composite uc
)
select
  r.user_id,
  r.displayname,
  r.location_norm as location,
  r.reputation,
  r.q_count,
  r.a_count,
  r.total_quality,
  r.avg_q_quality,
  r.avg_a_quality,
  r.median_post_score,
  r.badges_total,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.closed_questions,
  coalesce(tt.top_tag, '(none)') as top_tag,
  coalesce(tt.user_tag_q_count,0) as top_tag_qs,
  coalesce(tt.global_tag_q_count,0) as top_tag_global_qs,
  coalesce(al.avg_hours_to_accept, null) as avg_hours_to_accept,
  r.dup_links,
  r.related_links,
  r.comments_made,
  r.comment_score_sum,
  r.thanks_mentions,
  r.upmods_cast,
  r.downmods_cast,
  r.seconds_since_last_access,
  r.seconds_since_last_post,
  r.composite_score,
  r.composite_percentile,
  r.dense_rank_overall
from ranked r
left join top_tag tt on tt.user_id = r.user_id
left join answer_latency al on al.user_id = r.user_id
where
  -- nuanced predicate mixing string ops, null logic, and arithmetic
  (r.reputation >= 1000 or (r.q_count + r.a_count) >= 50)
  and (r.seconds_since_last_access is null or r.seconds_since_last_access < 60*60*24*365*2)
  and (
    position('stack' in lower(coalesce(r.location_norm,''))) > 0
    or r.badges_total >= 5
    or r.composite_percentile <= 20
  )
order by
  r.composite_percentile asc,
  r.composite_score desc,
  r.user_id
limit 250;