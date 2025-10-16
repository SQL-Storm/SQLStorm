-- {"query": "197.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2191} 
with
-- basic user aggregates
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.views,0) as views,
    coalesce(u.upvotes,0) as upvotes,
    coalesce(u.downvotes,0) as downvotes,
    -- counts and averages
    count(distinct q.id) filter (where q.posttypeid = 1) as question_count,
    count(distinct a.id) filter (where a.posttypeid = 2) as answer_count,
    avg(nullif(a.score,0)) filter (where a.posttypeid = 2) as avg_answer_score,
    sum(coalesce(p.score,0)) as total_post_score,
    max(p.lastactivitydate) as last_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.views, u.upvotes, u.downvotes
),
-- badge aggregates per user with conditional expressions and null logic
user_badges as (
  select
    b.userid,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    bool_or(b.tagbased) as has_tag_badge,
    string_agg(distinct b.name, '|' order by b.date desc) as recent_badge_names
  from badges b
  group by b.userid
),
-- tag exploded answers: parse Tags and attribute answers via parent question tags
exploded_tags as (
  select
    a.id as answer_id,
    q.id as question_id,
    trim(tg) as tag,
    a.owneruserid as user_id,
    a.score as answer_score,
    a.creationdate as answer_date
  from posts a
  join posts q on a.parentid = q.id and a.posttypeid = 2 and q.posttypeid = 1
  cross join lateral (
    select regexp_split_to_table(substring(q.tags from 2 for char_length(q.tags)-2), '><') as tg
  ) s
  where q.tags is not null
),
-- top tag per user by answer count + last answer date using window functions
user_top_tags as (
  select user_id, tag, answers_in_tag, last_answer_date,
         row_number() over (partition by user_id order by answers_in_tag desc, last_answer_date desc) as rn
  from (
    select
      e.user_id,
      e.tag,
      count(*) as answers_in_tag,
      max(e.answer_date) as last_answer_date
    from exploded_tags e
    group by e.user_id, e.tag
  ) t
),
-- median answer score per user using windowed percentile approximation
user_median_score as (
  select distinct user_id,
    percentile_disc(0.5) within group (order by answer_score) over (partition by user_id) as median_answer_score
  from exploded_tags
),
-- correlated subquery example: latest comment text on any of user's posts
user_latest_comment as (
  select u.id as user_id,
         (
           select c.text
           from comments c
           join posts p on c.postid = p.id
           where p.owneruserid = u.id
           order by c.creationdate desc
           limit 1
         ) as latest_comment,
         (
           select c.creationdate
           from comments c
           join posts p on c.postid = p.id
           where p.owneruserid = u.id
           order by c.creationdate desc
           limit 1
         ) as latest_comment_date
  from users u
),
-- combine everything with outer joins and null logic
user_summary as (
  select
    us.id,
    us.displayname,
    us.reputation,
    us.question_count,
    us.answer_count,
    coalesce(round(us.avg_answer_score::numeric,3),0) as avg_answer_score,
    coalesce(ums.median_answer_score, 0) as median_answer_score,
    coalesce(ub.badge_count,0) as badge_count,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ub.has_tag_badge,
    coalesce(utt.tag, '<<none>>') as top_tag,
    coalesce(utt.answers_in_tag, 0) as top_tag_answer_count,
    coalesce(ulc.latest_comment, '') as latest_comment_excerpt,
    coalesce(ulc.latest_comment_date, to_timestamp(0)) as latest_comment_date,
    -- activity score: weighted expression with null-safe math and powers
    (coalesce(us.answer_count,0) * 3 + coalesce(us.question_count,0) * 2 + coalesce(ub.badge_count,0) * 1.5
      + greatest(coalesce(us.views,0)/1000.0, 0) + coalesce(us.upvotes,0) - coalesce(us.downvotes,0)
      + coalesce(us.total_post_score,0)/10.0
    )::numeric as activity_score,
    us.last_activity
  from user_stats us
  left join user_badges ub on ub.userid = us.id
  left join user_median_score ums on ums.user_id = us.id
  left join user_top_tags utt on utt.user_id = us.id and utt.rn = 1
  left join user_latest_comment ulc on ulc.user_id = us.id
),
-- a union branch to include pseudo-rows summarizing global metrics (set operator usage)
global_summary as (
  select
    null::int as id,
    '<<GLOBAL AVERAGES>>'::varchar as displayname,
    round(avg(reputation)::numeric,2) as reputation,
    round(avg(question_count)::numeric,2) as question_count,
    round(avg(answer_count)::numeric,2) as answer_count,
    round(avg(avg_answer_score)::numeric,3) as avg_answer_score,
    round(avg(median_answer_score)::numeric,3) as median_answer_score,
    round(avg(badge_count)::numeric,2) as badge_count,
    null::int as gold_badges,
    null::int as silver_badges,
    null::int as bronze_badges,
    bool_or(has_tag_badge) as has_tag_badge,
    '<<GLOBAL>>'::varchar as top_tag,
    null::int as top_tag_answer_count,
    null::varchar as latest_comment_excerpt,
    max(latest_comment_date) as latest_comment_date,
    round(avg(activity_score)::numeric,3) as activity_score,
    max(last_activity) as last_activity
  from user_summary
)
-- final selection: union users and global, rich ordering, filters, correlated CASEs, string manipulations
select *
from (
  select 
    us.id,
    us.displayname,
    us.reputation,
    us.question_count,
    us.answer_count,
    us.avg_answer_score,
    us.median_answer_score,
    us.badge_count,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.has_tag_badge,
    -- create a leveled label with CASE and NULL logic
    case
      when us.activity_score >= 1000 then 'Platinum'
      when us.activity_score >= 500 then 'Gold'
      when us.activity_score >= 200 then 'Silver'
      when us.activity_score > 0 then 'Bronze'
      else 'New'
    end as activity_level,
    us.top_tag,
    us.top_tag_answer_count,
    -- show compact excerpt of latest comment: coalesce + substring + replace
    substring(replace(coalesce(us.latest_comment_excerpt,''), E'\n',' ') from 1 for 120) ||
      case when length(coalesce(us.latest_comment_excerpt,'')) > 120 then '...' else '' end as latest_comment_excerpt,
    us.latest_comment_date,
    -- computed engagement ratio with division by null-safe greatest
    round( (coalesce(us.answer_count,0)::numeric / greatest(1, nullif(us.question_count,0) ) )::numeric,3) as answer_to_question_ratio,
    round(us.activity_score::numeric,3) as activity_score,
    us.last_activity
  from user_summary us
  where (us.answer_count + us.question_count) > 0
    and us.reputation is not null
  union all
  select
    gs.id, gs.displayname, gs.reputation, gs.question_count, gs.answer_count, gs.avg_answer_score, gs.median_answer_score,
    gs.badge_count, gs.gold_badges, gs.silver_badges, gs.bronze_badges, gs.has_tag_badge,
    'Aggregate'::varchar as activity_level,
    gs.top_tag, gs.top_tag_answer_count, gs.latest_comment_excerpt, gs.latest_comment_date, null::numeric as answer_to_question_ratio,
    gs.activity_score, gs.last_activity
  from global_summary gs
) final
-- rank and window analysis over the combined set: top 200 by activity_score, also compute moving average
order by activity_score desc nulls last, reputation desc nulls last
limit 200;