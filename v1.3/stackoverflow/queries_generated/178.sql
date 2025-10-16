-- {"query": "178.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2632} 
with
-- base posts split
q as (
  select p.* 
  from posts p
  where p.posttypeid = 1
),
a as (
  select p.*
  from posts p
  where p.posttypeid = 2
),

-- per-user aggregates
user_post_agg as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as question_count,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answer_count,
    coalesce(avg(p.score) filter (where p.posttypeid in (1,2)),0) as avg_post_score,
    coalesce(max(p.score) filter (where p.posttypeid in (1,2)),0) as max_post_score,
    coalesce(sum(case when p.creationdate >= now() - interval '30 days' then 1 else 0 end),0) as recent_posts_30d,
    -- boolean-ish flags with null logic
    case when exists (select 1 from posts p2 where p2.owneruserid = u.id and p2.acceptedanswerid is not null) then 1 else 0 end as has_question_with_accepted,
    case when u.views is null then 0 else u.views end as user_views,
    u.creationdate
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.views, u.creationdate
),

-- badge counts with conditional weighting and null handling
badge_weights as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 5 when b.class = 2 then 3 when b.class = 3 then 1 else 0 end) as badge_score
  from badges b
  group by b.userid
),

-- top-scoring post per user using window functions
top_posts as (
  select *
  from (
    select p.*,
      row_number() over (partition by p.owneruserid order by p.score desc nulls last, p.viewcount desc nulls last, p.creationdate desc nulls last) as rn
    from posts p
    where p.owneruserid is not null
  ) t
  where t.rn = 1
),

-- per-user "fast answer" metric: average hours between question creation and first answer from this user to that question (correlated subquery)
fast_answer as (
  select u.id as user_id,
    avg(
      extract(epoch from (
        (select min(a2.creationdate) from posts a2 where a2.posttypeid=2 and a2.parentid = q.id and a2.owneruserid = u.id)
        - q.creationdate
      )) / 3600.0
    ) filter (where (select min(a2.creationdate) from posts a2 where a2.posttypeid=2 and a2.parentid = q.id and a2.owneruserid = u.id) is not null) as avg_hours_to_first_answer
  from users u
  join posts q on q.posttypeid = 1
  group by u.id
),

-- extract tags per user by splitting Tags string and counting occurrences (uses Postgres style string_to_array)
user_tag_counts as (
  select owneruserid as user_id,
         lower(trim(both ' ' from tag)) as tag,
         count(*) as tag_count
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as tag
  ) s
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
  group by owneruserid, lower(trim(both ' ' from tag))
),

-- most frequent tag per user (correlated tie-break)
top_tag_per_user as (
  select utc.user_id, utc.tag, utc.tag_count
  from (
    select utc.*,
      row_number() over (partition by utc.user_id order by utc.tag_count desc, utc.tag) as rn
    from user_tag_counts utc
  ) utc
  where utc.rn = 1
),

-- recent activity windowed metrics per user (last 90 days)
recent_activity as (
  select
    u.id as user_id,
    sum(case when p.creationdate >= now()- interval '90 days' then 1 else 0 end) as posts_90d,
    sum(case when c.creationdate >= now()- interval '90 days' then 1 else 0 end) as comments_90d,
    max(p.lastactivitydate) as last_post_activity,
    max(c.creationdate) as last_comment_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  group by u.id
),

-- combine everything into a single rich metric table
rich_user_metrics as (
  select
    upa.user_id,
    upa.displayname,
    upa.reputation,
    coalesce(bw.badge_count,0) as badge_count,
    coalesce(bw.badge_score,0) as badge_score,
    upa.question_count,
    upa.answer_count,
    upa.avg_post_score,
    upa.max_post_score,
    upa.recent_posts_30d,
    coalesce(fa.avg_hours_to_first_answer, null) as avg_hours_to_first_answer,
    tp.title as top_post_title,
    tp.id as top_post_id,
    tp.score as top_post_score,
    tt.tag as top_tag,
    tt.tag_count as top_tag_count,
    ra.posts_90d,
    ra.comments_90d,
    -- synthetic composite ranking (complex expression with null logic and weights)
    (
      (coalesce(upa.reputation,0)::numeric / nullif(greatest(1, (select max(reputation) from users)),0) * 50.0)
      + (coalesce(bw.badge_score,0) * 1.5)
      + (coalesce(upa.avg_post_score,0) * 2.0)
      + (case when upa.has_question_with_accepted = 1 then 10 else 0 end)
      - (coalesce(fa.avg_hours_to_first_answer, 72) / 72.0 * 5.0)
      + (coalesce(ra.posts_90d,0) * 0.5)
    ) as composite_score,
    upa.creationdate,
    upa.user_views
  from user_post_agg upa
  left join badge_weights bw on bw.userid = upa.user_id
  left join top_posts tp on tp.owneruserid = upa.user_id
  left join top_tag_per_user tt on tt.user_id = upa.user_id
  left join fast_answer fa on fa.user_id = upa.user_id
  left join recent_activity ra on ra.user_id = upa.user_id
)

-- final select: elaborate query combining CTE, windowing, set operators, and complex predicates
select
  rum.user_id,
  rum.displayname,
  rum.reputation,
  rum.question_count,
  rum.answer_count,
  rum.top_tag,
  rum.top_tag_count,
  rum.top_post_id,
  left(coalesce(rum.top_post_title, '<no title>'), 120) as top_post_title_snippet,
  rum.top_post_score,
  rum.badge_count,
  rum.badge_score,
  round(rum.avg_post_score::numeric,2) as avg_post_score,
  coalesce(round(rum.avg_hours_to_first_answer::numeric,2), null) as avg_hours_to_first_answer,
  round(rum.composite_score::numeric,3) as composite_score,
  rum.posts_90d,
  rum.comments_90d,
  case
    when rum.reputation >= 100000 then 'Legend'
    when rum.reputation >= 10000 then 'Expert'
    when rum.reputation >= 1000 then 'Active'
    when rum.reputation >= 100 then 'Contributor'
    else 'Newcomer'
  end as reputation_band,
  -- demonstration of string expression and NULL logic
  concat(
    coalesce(rum.displayname,'<anon>'),
    ' (', coalesce(nullif(trim(rum.top_tag),''), 'no-tag'), ')',
    ' / rep=', coalesce(rum.reputation::text,'0'),
    ' / badges=', coalesce(rum.badge_count::text,'0')
  ) as summary,
  rum.creationdate,
  rum.user_views
from rich_user_metrics rum
where
  -- complicated predicate: users who either have a high composite score or recent activity and at least one badge, excluding community-like accounts
  (
    rum.composite_score >= 20
    or (rum.posts_90d >= 3 and rum.badge_count >= 1)
  )
  and not (rum.displayname ilike '%community%' or rum.user_id = -1)
order by rum.composite_score desc nulls last, rum.reputation desc nulls last
limit 250

union all

-- add a small diagnostic row-set produced by a set operator combining lows and highs (ensures use of set operator)
select
  -1 as user_id,
  'Aggregate:Top-and-Bottom' as displayname,
  (select max(reputation) from users) as reputation,
  (select count(*) filter (where posttypeid=1) from posts) as question_count,
  (select count(*) filter (where posttypeid=2) from posts) as answer_count,
  null::varchar as top_tag,
  null::int as top_tag_count,
  null::int as top_post_id,
  'AGG_ROW' as top_post_title_snippet,
  null::int as top_post_score,
  (select count(*) from badges) as badge_count,
  null::numeric as badge_score,
  null::numeric as avg_post_score,
  null::numeric as avg_hours_to_first_answer,
  null::numeric as composite_score,
  null::int as posts_90d,
  null::int as comments_90d,
  'Sys' as reputation_band,
  'Aggregate summary' as summary,
  null::timestamp as creationdate,
  null::int as user_views

except

-- exclude any user that has zero posts and zero badges to stress-exercise EXCEPT
select u.id, u.displayname, u.reputation, 0,0,null,null,null,null,0,null,null,null,null,null,null,null,null,null,null
from users u
where not exists (select 1 from posts p where p.owneruserid = u.id) and not exists (select 1 from badges b where b.userid = u.id)
;