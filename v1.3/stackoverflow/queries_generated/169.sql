-- {"query": "169.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2323} 
with
-- basic aggregates per user
user_posts as (
  select
    u.id as user_id,
    u.displayname,
    count(p.id) filter (where p.posttypeid = 1) as questions_count,
    count(p.id) filter (where p.posttypeid = 2) as answers_count,
    sum(p.score) as total_post_score,
    avg(nullif(p.score,0)) as avg_nonzero_score,
    max(p.lastactivitydate) as last_activity,
    min(u.creationdate) as user_created
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname
),
-- votes summary joined with posts to include posts without votes (full outer-ish behavior via aggregation then join)
post_votes as (
  select
    p.id as post_id,
    p.owneruserid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    count(v.id) as total_votes
  from posts p
  left join votes v on v.postid = p.id
  group by p.id, p.owneruserid
),
-- per-user votes aggregates (including users with no posts)
user_votes as (
  select
    u.id as user_id,
    coalesce(sum(pv.upvotes),0) as upvotes_received,
    coalesce(sum(pv.downvotes),0) as downvotes_received,
    coalesce(sum(pv.favorites),0) as favorites_received,
    coalesce(sum(pv.total_votes),0) as total_votes_received
  from users u
  left join post_votes pv on pv.owneruserid = u.id
  group by u.id
),
-- tag explosion for questions into (user, tag) pairs using the documented split expression
question_tags as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    tag
  from posts q
  cross join lateral (
    select unnest(string_to_array(substring(q.tags,2,length(q.tags)-2), '><')) as tag
  ) t
  where q.posttypeid = 1 and q.tags is not null
),
-- per-user tag popularity: count of questions per tag and last question date per tag
user_tag_stats as (
  select
    qt.user_id,
    qt.tag,
    count(*) as questions_with_tag,
    max(q.creationdate) as last_tag_activity
  from question_tags qt
  join posts q on q.id = qt.question_id
  group by qt.user_id, qt.tag
),
-- pick top 3 tags per user with row_number
top_tags as (
  select
    uts.user_id,
    string_agg(uts.tag || ':' || uts.questions_with_tag, ', ' order by uts.questions_with_tag desc, uts.tag) filter (where rn <= 3) as top_3_tags
  from (
    select
      uts.*,
      row_number() over (partition by uts.user_id order by uts.questions_with_tag desc, uts.tag) as rn
    from user_tag_stats uts
  ) uts
  group by uts.user_id
),
-- compute per-user acceptance rate: how many of their answers were accepted
accepted_info as (
  select
    a.owneruserid as user_id,
    count(a.id) filter (where exists (select 1 from posts q where q.acceptedanswerid = a.id)) as accepted_as_answer_count,
    count(a.id) as answers_total_for_accept
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
-- average answer latency: for answers with a parent question, compute time diff between question creation and answer creation
answer_latency as (
  select
    a.owneruserid as user_id,
    avg(extract(epoch from (a.creationdate - q.creationdate))) filter (where a.creationdate is not null and q.creationdate is not null) as avg_answer_latency_seconds,
    percentile_cont(0.75) within group (order by extract(epoch from (a.creationdate - q.creationdate))) filter (where a.creationdate is not null and q.creationdate is not null) as p75_latency_seconds
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
  group by a.owneruserid
),
-- badges per user with tag-based split and class counts
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    string_agg(distinct (case when b.tagbased = true then b.name else null end), ', ') filter (where sum(case when b.tagbased = true then 1 else 0 end) > 0) over (partition by b.userid) as tag_based_badges
  from badges b
  group by b.userid
),
-- recent intensive activity: count of edits, closes, migrations from posthistory (complex predicates & null handling)
recent_history as (
  select
    ph.userid as user_id,
    sum(case when ph.posthistorytypeid in (4,5,6,24) then 1 else 0 end) as edits_made,
    sum(case when ph.posthistorytypeid in (10,11,35,36) then 1 else 0 end) as closure_migrations,
    max(ph.creationdate) as last_history_date
  from posthistory ph
  group by ph.userid
),
-- combine everything into a final ranking set, include some correlated subqueries for exotic stats
combined as (
  select
    u.id as user_id,
    u.displayname,
    up.questions_count,
    up.answers_count,
    uv.upvotes_received,
    uv.downvotes_received,
    uv.favorites_received,
    coalesce(ai.accepted_as_answer_count,0) as accepted_answers,
    coalesce(ai.answers_total_for_accept,0) as answers_for_accept,
    case when coalesce(ai.answers_total_for_accept,0) = 0 then null
         else round(100.0 * coalesce(ai.accepted_as_answer_count,0) / ai.answers_total_for_accept,2) end as accepted_rate_pct,
    round(coalesce(ap.avg_answer_latency_seconds,0)) as avg_answer_latency_seconds,
    round(coalesce(ap.p75_latency_seconds,0)) as p75_answer_latency_seconds,
    tb.top_3_tags,
    ub.badge_total,
    ub.gold,
    ub.silver,
    ub.bronze,
    rh.edits_made,
    rh.closure_migrations,
    up.total_post_score,
    up.avg_nonzero_score,
    u.reputation,
    u.views,
    u.lastaccessdate,
    up.last_activity,
    -- correlated subquery: find the id and title of the highest scored question this user asked (null-safe)
    (select row_to_json(r) from (
       select p.id, p.title, p.score
       from posts p
       where p.posttypeid = 1 and p.owneruserid = u.id
       order by p.score desc nulls last, p.viewcount desc nulls last
       limit 1
    ) r) as top_question_snapshot,
    -- correlated subquery: whether the user has any posts with null body indicating odd data
    exists (select 1 from posts p2 where p2.owneruserid = u.id and p2.body is null) as has_null_bodies,
    -- a synthetic complex expression combining null logic and string functions
    case
      when u.websiteurl is not null then
        lower(regexp_replace(coalesce(u.websiteurl,''), 'https?://(www\\.)?', '', 'i'))
      when u.location is not null then
        left(regexp_replace(u.location, '\\s+', ' ', 'g'), 50)
      else
        'n/a'
    end as contact_hint,
    -- mark super-active via expression mixing counts and percentile via window
    row_number() over (order by up.total_post_score desc nulls last, uv.upvotes_received desc) as score_rank
  from users u
  left join user_posts up on up.user_id = u.id
  left join user_votes uv on uv.user_id = u.id
  left join accepted_info ai on ai.user_id = u.id
  left join answer_latency ap on ap.user_id = u.id
  left join top_tags tb on tb.user_id = u.id
  left join user_badges ub on ub.user_id = u.id
  left join recent_history rh on rh.user_id = u.id
)
select
  c.*,
  -- additional windowed metrics computed at the final select level
  dense_rank() over (order by c.reputation desc nulls last) as reputation_rank,
  percentile_cont(0.5) within group (order by c.avg_nonzero_score) over () as global_median_avg_score,
  -- combine with a set operator subquery to show a synthetic comparison: count of users above and below median reputation
  (select concat('above=', count(*)) from combined c2 where c2.reputation > (select percentile_cont(0.5) within group (order by reputation) from combined)) as users_above_median_reputation,
  (select concat('below=', count(*)) from combined c3 where c3.reputation <= (select percentile_cont(0.5) within group (order by reputation) from combined)) as users_below_median_reputation
from combined c
where c.questions_count + coalesce(c.answers_count,0) > 0
order by c.score_rank
limit 100;