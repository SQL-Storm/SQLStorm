-- {"query": "753.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3215} 
with
-- recent window for activity
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
-- explode tags
q_tags as (
  select
    p.id as question_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  from recent_posts p
  where p.posttypeid = 1
),
-- tag popularity windowed
tag_popularity as (
  select
    qt.tag,
    count(*) as tag_q_count,
    sum(coalesce(p.viewcount,0)) as tag_views,
    avg(coalesce(p.score,0)) as avg_q_score,
    dense_rank() over(order by count(*) desc, sum(coalesce(p.viewcount,0)) desc) as tag_rank_by_usage
  from q_tags qt
  join posts p on p.id = qt.question_id
  group by qt.tag
),
-- user activity summary with window functions
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers,
    count(distinct c.id) as comments,
    sum(coalesce(p.score,0)) as total_post_score,
    sum(coalesce(v2.votes_up,0)) as upvotes_cast,
    sum(coalesce(v3.votes_down,0)) as downvotes_cast,
    row_number() over (partition by (u.location is null) order by u.reputation desc, u.id) as rn_by_locnull,
    ntile(10) over (order by u.reputation desc) as rep_decile
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join (
    select userid, count(*) as votes_up
    from votes
    where votetypeid = 2
    group by userid
  ) v2 on v2.userid = u.id
  left join (
    select userid, count(*) as votes_down
    from votes
    where votetypeid = 3
    group by userid
  ) v3 on v3.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate
),
-- answers and their parent question relationship + lag/lead metrics
answer_metrics as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_created,
    q.owneruserid as asker_id,
    q.acceptedanswerid,
    q.score as question_score,
    q.viewcount as question_views,
    lead(a.score) over(partition by a.parentid order by a.score desc, a.id) as next_answer_score,
    lag(a.score) over(partition by a.parentid order by a.score desc, a.id) as prev_answer_score,
    rank() over(partition by a.parentid order by a.score desc, a.id) as answer_rank_by_score
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
-- compute close/reopen/migrate events per question
question_events as (
  select
    ph.postid as question_id,
    sum(case when ph.posthistorytypeid in (10) then 1 else 0 end) as close_events,
    sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
    sum(case when ph.posthistorytypeid in (35,36,17) then 1 else 0 end) as migrate_events,
    max(ph.creationdate) as last_event_at,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
  from posthistory ph
  join posts q on q.id = ph.postid and q.posttypeid = 1
  where ph.posthistorytypeid in (10,11,17,35,36)
  group by ph.postid
),
-- duplicate links (set operators)
dup_links as (
  select postid as question_id, relatedpostid as original_id, creationdate as dup_marked_at
  from postlinks
  where linktypeid = 3
),
-- badges summary per user with conditional aggregation
badge_summary as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
-- activity score index per question combining multiple factors
question_composite as (
  select
    q.id as question_id,
    q.title,
    q.tags,
    q.score as q_score,
    q.viewcount as q_views,
    q.creationdate as q_created,
    coalesce(q.answercount,0) as answer_count,
    qa.answer_id as accepted_answer_id,
    -- composite score uses log, sqrt, null logic, string length etc.
    (
      coalesce(q.score,0) * 3
      + sqrt(greatest(coalesce(q.viewcount,0),0))
      + coalesce(q.answercount,0) * 4
      + case when q.acceptedanswerid is not null then 15 else 0 end
      - coalesce(ev.close_events,0) * 5
      + coalesce(ev.reopen_events,0) * 2
    )::numeric(18,4) as composite_index,
    ev.close_events,
    ev.reopen_events,
    ev.migrate_events,
    ev.last_close_reason_raw,
    dl.original_id as duplicate_of
  from posts q
  left join (select id as answer_id, parentid from posts where id in (select acceptedanswerid from posts where acceptedanswerid is not null)) qa
    on qa.parentid = q.id
  left join question_events ev on ev.question_id = q.id
  left join dup_links dl on dl.question_id = q.id
  where q.posttypeid = 1
),
-- rank questions within tag and overall
ranked_questions as (
  select
    qc.*,
    t.tag,
    tp.tag_q_count,
    tp.tag_rank_by_usage,
    row_number() over(order by qc.composite_index desc, qc.q_views desc, qc.q_score desc) as global_rank,
    row_number() over(partition by t.tag order by qc.composite_index desc) as rank_in_tag
  from question_composite qc
  left join lateral (
    select unnest(string_to_array(substring(qc.tags, 2, length(qc.tags)-2), '><')) as tag
  ) t on true
  left join tag_popularity tp on tp.tag = t.tag
),
-- compute commenter influence on each question using correlated subquery
comment_influence as (
  select
    c.postid as question_id,
    count(*) as comments_count,
    sum(coalesce(c.score,0)) as comments_score,
    (
      select avg(u2.reputation)
      from comments c2
      join users u2 on u2.id = c2.userid
      where c2.postid = c.postid
    ) as avg_commenter_rep
  from comments c
  join posts q on q.id = c.postid and q.posttypeid = 1
  group by c.postid
),
-- per-user cross metrics combining posts, votes and badges
user_cross as (
  select
    ua.user_id,
    ua.displayname,
    ua.reputation,
    ua.rep_decile,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(bs.silver_badges,0) as silver_badges,
    coalesce(bs.bronze_badges,0) as bronze_badges,
    coalesce(bs.tag_badges,0) as tag_badges,
    ua.questions,
    ua.answers,
    ua.comments,
    ua.upvotes_cast,
    ua.downvotes_cast,
    ua.total_post_score,
    (coalesce(ua.answers,0) * 2 + coalesce(ua.questions,0) + coalesce(ua.comments,0) * 0.25 + coalesce(ua.upvotes_cast,0) * 0.1 - coalesce(ua.downvotes_cast,0) * 0.2 + coalesce(bs.gold_badges,0) * 3 + coalesce(bs.silver_badges,0) * 1.5 + coalesce(bs.bronze_badges,0) * 0.5)::numeric(18,3) as activity_score
  from user_activity ua
  left join badge_summary bs on bs.userid = ua.user_id
),
-- find "power users" per tag: users with high activity and strong answers to questions in the tag
tag_user_strength as (
  select
    t.tag,
    u.id as user_id,
    u.displayname,
    count(distinct a.answer_id) as answers_in_tag,
    sum(case when a.answer_id = q.acceptedanswerid then 1 else 0 end) as accepted_in_tag,
    avg(a.answer_score) as avg_answer_score_tag,
    max(a.answer_score) as max_answer_score_tag,
    sum(case when a.answer_rank_by_score = 1 then 1 else 0 end) as top_scored_answers_in_tag
  from q_tags t
  join posts q on q.id = t.question_id
  join answer_metrics a on a.question_id = q.id
  join users u on u.id = a.answerer_id
  group by t.tag, u.id, u.displayname
),
-- normalize by tag volume
tag_user_strength_norm as (
  select
    tus.tag,
    tus.user_id,
    tus.displayname,
    tus.answers_in_tag,
    tus.accepted_in_tag,
    tus.avg_answer_score_tag,
    tus.max_answer_score_tag,
    tus.top_scored_answers_in_tag,
    tp.tag_q_count,
    round( (tus.answers_in_tag::numeric / nullif(tp.tag_q_count,0)) * 1000, 4) as answers_per_1k_questions,
    rank() over(partition by tus.tag order by tus.accepted_in_tag desc, tus.top_scored_answers_in_tag desc, tus.avg_answer_score_tag desc, tus.answers_in_tag desc) as rank_user_in_tag
  from tag_user_strength tus
  join tag_popularity tp on tp.tag = tus.tag
),
-- heavy join bringing everything together
final_agg as (
  select
    rq.question_id,
    rq.title,
    coalesce(rq.tag, '(untagged)') as tag,
    rq.global_rank,
    rq.rank_in_tag,
    rq.tag_rank_by_usage,
    rq.composite_index,
    rq.q_score,
    rq.q_views,
    rq.answer_count,
    rq.duplicate_of,
    rq.close_events,
    rq.reopen_events,
    rq.migrate_events,
    ci.comments_count,
    ci.comments_score,
    ci.avg_commenter_rep,
    max(case when tusn.rank_user_in_tag = 1 then tusn.displayname end) as top_helper_displayname,
    max(case when tusn.rank_user_in_tag = 1 then tusn.user_id end) as top_helper_userid,
    max(case when tusn.rank_user_in_tag = 1 then tusn.answers_in_tag end) as top_helper_answers_in_tag
  from ranked_questions rq
  left join comment_influence ci on ci.question_id = rq.question_id
  left join tag_user_strength_norm tusn on tusn.tag = rq.tag
  group by
    rq.question_id, rq.title, rq.tag, rq.global_rank, rq.rank_in_tag, rq.tag_rank_by_usage,
    rq.composite_index, rq.q_score, rq.q_views, rq.answer_count, rq.duplicate_of,
    rq.close_events, rq.reopen_events, rq.migrate_events, ci.comments_count, ci.comments_score, ci.avg_commenter_rep
)
select
  fa.question_id,
  left(coalesce(fa.title,''), 120) as title_snippet,
  fa.tag,
  fa.global_rank,
  fa.rank_in_tag,
  fa.tag_rank_by_usage,
  round(fa.composite_index, 3) as composite_index,
  fa.q_score,
  fa.q_views,
  fa.answer_count,
  coalesce(fa.comments_count,0) as comments_count,
  coalesce(fa.comments_score,0) as comments_score,
  round(coalesce(fa.avg_commenter_rep,0),2) as avg_commenter_rep,
  coalesce(fa.top_helper_displayname, 'n/a') as top_helper_displayname,
  fa.top_helper_userid,
  fa.top_helper_answers_in_tag,
  -- string expressions and null logic
  case
    when fa.duplicate_of is not null then 'DUP->' || fa.duplicate_of::varchar
    when fa.close_events > 0 then 'CLOSED'
    when fa.migrate_events > 0 then 'MIGRATED'
    else 'OPEN'
  end as status,
  -- correlated scalar subquery: favorite count via votes table (pre-2022)
  coalesce((
    select count(*) from votes v where v.postid = fa.question_id and v.votetypeid = 5
  ), 0) as favorites_legacy,
  -- percentile of views within tag
  percent_rank() over(partition by fa.tag order by fa.q_views) as view_percentile_in_tag
from final_agg fa
where
  -- complicated predicates mixing nulls, text, and math
  (fa.composite_index > coalesce((select avg(qc2.composite_index) from question_composite qc2), 0))
  and (
    fa.tag in (
      select tag from tag_popularity where tag_rank_by_usage <= 50
      union
      select tag from tag_popularity where avg_q_score >= (
        select avg(avg_q_score) from tag_popularity
      )
    )
    or fa.rank_in_tag <= 3
  )
  and (
    fa.title is not null
    and length(trim(fa.title)) > 0
    and position('?' in fa.title) = 0
  )
order by
  fa.global_rank
fetch first 200 rows only;