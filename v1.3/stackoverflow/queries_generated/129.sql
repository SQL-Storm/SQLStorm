-- {"query": "129.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2541} 
with
-- basic aggregates per user
user_posts as (
  select
    u.id as user_id,
    u.displayname,
    count(p.id) filter (where p.posttypeid = 1) as questions_count,
    count(p.id) filter (where p.posttypeid = 2) as answers_count,
    sum(p.score) filter (where p.posttypeid in (1,2)) as total_post_score,
    sum(p.viewcount) filter (where p.posttypeid = 1) as total_question_views,
    max(p.lastactivitydate) as last_activity,
    min(u.creationdate) as user_created
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname
),
-- badge weighted score (gold=5 silver=2 bronze=1) with recency decay
badge_scores as (
  select
    b.userid,
    sum(
      case b.class when 1 then 5 when 2 then 2 when 3 then 1 else 0 end
      * greatest(0.1, 1 - extract(epoch from (now() - b.date))/ (60*60*24*365 * 3)) -- 3-year half-life-ish decay
    ) as badge_weighted
  from badges b
  group by b.userid
),
-- votes given/received and favorites/bookmarks count
vote_stats as (
  select
    p.owneruserid as user_id,
    sum(case v.votetypeid when 2 then 1 when 3 then -1 else 0 end) as net_votes_on_posts,
    count(v.id) filter (where v.votetypeid = 5) as favorites_received
  from posts p
  left join votes v on v.postid = p.id
  group by p.owneruserid
),
-- comments activity
comment_stats as (
  select
    coalesce(c.userid, -1) as user_id,
    count(*) as comments_count,
    max(c.creationdate) as last_comment
  from comments c
  group by coalesce(c.userid, -1)
),
-- tag diversity via exploding tags string (Postgres style)
tag_usage as (
  select
    p.owneruserid as user_id,
    lower(trim(t)) as tag,
    count(*) as cnt
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''), 2, char_length(coalesce(p.tags,'')) - 2), '><')) as t
  ) tags_expanded
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
  group by p.owneruserid, lower(trim(t))
),
tag_diversity as (
  select
    user_id,
    count(distinct tag) as distinct_tags,
    sum(cnt) as total_tagged_questions
  from tag_usage
  group by user_id
),
-- recent activity and edits from posthistory
recent_edits as (
  select
    ph.userid,
    count(*) filter (where ph.creationdate > now() - interval '180 days') as edits_180d,
    count(*) as total_edits,
    max(ph.creationdate) as last_edit
  from posthistory ph
  group by ph.userid
),
-- correlated subquery: acceptance rate per user (answers accepted / answers posted)
acceptance_rate as (
  select
    a.owneruserid as user_id,
    nullif(sum(case when q.acceptedanswerid = a.id then 1 else 0 end),0)::float / nullif(count(a.id),0) as accept_rate
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
  group by a.owneruserid
),
-- a heavy CTE using window functions over posts to get user-level percentiles and trends
post_time_series as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) as posts_in_month,
    sum(p.score) as score_in_month,
    avg(p.viewcount) filter (where p.posttypeid = 1) as avg_q_views_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
user_trends as (
  select
    user_id,
    avg(posts_in_month) over (partition by user_id) as avg_posts_month,
    stddev_pop(posts_in_month) over (partition by user_id) as sd_posts_month,
    max(posts_in_month) over (partition by user_id) as peak_posts_month,
    min(posts_in_month) over (partition by user_id) as low_posts_month
  from post_time_series
),
-- combine main metrics
user_metrics as (
  select
    u.user_id,
    u.displayname,
    u.questions_count,
    u.answers_count,
    coalesce(u.total_post_score,0) as total_post_score,
    coalesce(u.total_question_views,0) as total_question_views,
    coalesce(b.badge_weighted,0) as badge_weighted,
    coalesce(v.net_votes_on_posts,0) as net_votes_on_posts,
    coalesce(c.comments_count,0) as comments_count,
    coalesce(t.distinct_tags,0) as distinct_tags,
    coalesce(a.accept_rate,0) as accept_rate,
    coalesce(r.edits_180d,0) as edits_180d,
    greatest(
      0,
      (coalesce(u.answers_count,0) * 1.5)
      + (coalesce(u.questions_count,0) * 1.0)
      + (coalesce(u.total_post_score,0) * 0.3)
      + (coalesce(b.badge_weighted,0) * 4)
      + (coalesce(v.net_votes_on_posts,0) * 0.5)
      + (coalesce(c.comments_count,0) * 0.1)
      + (coalesce(t.distinct_tags,0) * 0.2)
      + (coalesce(a.accept_rate,0) * 20)
      + (coalesce(r.edits_180d,0) * 0.2)
      - (coalesce(u.total_question_views,0) / nullif(1 + coalesce(u.questions_count,0),1)) * 0.01
    ) as composite_score
  from user_posts u
  left join badge_scores b on b.userid = u.user_id
  left join vote_stats v on v.user_id = u.user_id
  left join comment_stats c on c.user_id = u.user_id
  left join tag_diversity t on t.user_id = u.user_id
  left join acceptance_rate a on a.user_id = u.user_id
  left join recent_edits r on r.userid = u.user_id
),
-- two sets: regular users and community/anonymous pseudo-user combined via set operator
ranked_users as (
  select
    um.*,
    row_number() over (order by composite_score desc, total_post_score desc, answers_count desc nulls last) as rn,
    dense_rank() over (order by composite_score desc) as dr,
    percentile_cont(0.5) within group (order by composite_score) over () as median_score
  from user_metrics um
),
-- create an artificial aggregated row summarizing "top contributors" using set operator
top_summary as (
  select
    null::int as user_id,
    'Top contributors aggregate'::varchar as displayname,
    sum(questions_count) as questions_count,
    sum(answers_count) as answers_count,
    sum(total_post_score)::int as total_post_score,
    sum(total_question_views)::int as total_question_views,
    sum(badge_weighted) as badge_weighted,
    sum(net_votes_on_posts)::int as net_votes_on_posts,
    sum(comments_count)::int as comments_count,
    sum(distinct_tags)::int as distinct_tags,
    avg(accept_rate)::float as accept_rate,
    sum(edits_180d)::int as edits_180d,
    avg(composite_score)::float as composite_score,
    null::int as rn,
    null::int as dr,
    null::float as median_score
  from user_metrics
  where composite_score >= (
    select percentile_cont(0.90) within group (order by composite_score) from user_metrics
  )
)
-- final select: union the ranked top N users with the summary aggregated row
select *
from (
  select
    ru.user_id,
    ru.displayname,
    ru.questions_count,
    ru.answers_count,
    ru.total_post_score,
    ru.total_question_views,
    ru.badge_weighted,
    ru.net_votes_on_posts,
    ru.comments_count,
    ru.distinct_tags,
    ru.accept_rate,
    ru.edits_180d,
    ru.composite_score,
    ru.rn,
    ru.dr,
    ru.median_score,
    -- add explanatory computed fields and string ops
    concat(
      coalesce(ru.displayname,'[unknown]'),
      ' (Q=', coalesce(ru.questions_count::text,'0'),
      ', A=', coalesce(ru.answers_count::text,'0'),
      ', S=', coalesce(ru.total_post_score::text,'0'),
      ')'
    ) as short_label,
    case
      when ru.accept_rate is null then 'no-data'
      when ru.accept_rate >= 0.5 then 'high-accept'
      when ru.accept_rate >= 0.2 then 'mid-accept'
      else 'low-accept'
    end as accept_bucket,
    -- null-aware substring of displayname
    coalesce(nullif(substring(ru.displayname from 1 for 20),''),'[anonymous]') as display_snippet
  from ranked_users ru
  where ru.rn <= 50

  union all

  select
    ts.user_id,
    ts.displayname,
    ts.questions_count,
    ts.answers_count,
    ts.total_post_score,
    ts.total_question_views,
    ts.badge_weighted,
    ts.net_votes_on_posts,
    ts.comments_count,
    ts.distinct_tags,
    ts.accept_rate,
    ts.edits_180d,
    ts.composite_score,
    ts.rn,
    ts.dr,
    ts.median_score,
    concat(ts.displayname,' (aggregate)') as short_label,
    'aggregate' as accept_bucket,
    left(ts.displayname,20) as display_snippet
  from top_summary ts
) final
order by composite_score desc nulls last, answers_count desc nulls last, questions_count desc nulls last
limit 51;