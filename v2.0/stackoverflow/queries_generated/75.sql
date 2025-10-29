-- {"query": "75.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3349} 
with
-- recent active users with reputation tiers
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    case
      when u.reputation >= 100000 then 'Legend'
      when u.reputation >= 25000 then 'Elite'
      when u.reputation >= 10000 then 'Pro'
      when u.reputation >= 3000 then 'Advanced'
      when u.reputation >= 1000 then 'Intermediate'
      else 'Novice'
    end as rep_tier
  from users u
  where u.lastaccessdate >= now() - interval '365 days'
),
-- aggregate user activity and null-safe ratios
user_activity as (
  select
    u.user_id,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers,
    coalesce(sum(p.score) filter (where p.posttypeid in (1,2)), 0) as post_score,
    coalesce(sum(p.viewcount) filter (where p.posttypeid = 1), 0) as question_views,
    coalesce(sum(ca.cnt), 0) as comments_made,
    coalesce(sum(vu.upvotes), 0) as upvotes_received,
    coalesce(sum(vd.downvotes), 0) as downvotes_received,
    coalesce(sum(b_bronze.cnt),0) as bronze_badges,
    coalesce(sum(b_silver.cnt),0) as silver_badges,
    coalesce(sum(b_gold.cnt),0) as gold_badges
  from active_users u
  left join posts p
    on p.owneruserid = u.user_id
  left join lateral (
    select count(*) as cnt
    from comments c
    where c.userid = u.user_id
  ) ca on true
  left join lateral (
    select count(*) as upvotes
    from votes v
    join posts pp on pp.id = v.postid
    where v.votetypeid = 2 and pp.owneruserid = u.user_id
  ) vu on true
  left join lateral (
    select count(*) as downvotes
    from votes v
    join posts pp on pp.id = v.postid
    where v.votetypeid = 3 and pp.owneruserid = u.user_id
  ) vd on true
  left join lateral (
    select count(*) as cnt from badges b where b.userid = u.user_id and b.class = 3
  ) b_bronze on true
  left join lateral (
    select count(*) as cnt from badges b where b.userid = u.user_id and b.class = 2
  ) b_silver on true
  left join lateral (
    select count(*) as cnt from badges b where b.userid = u.user_id and b.class = 1
  ) b_gold on true
  group by u.user_id
),
-- windowed ranks and dense ranks per reputation tier
ranked_users as (
  select
    au.user_id,
    au.displayname,
    au.reputation,
    au.rep_tier,
    ua.total_posts,
    ua.questions,
    ua.answers,
    ua.post_score,
    ua.question_views,
    ua.comments_made,
    ua.upvotes_received,
    ua.downvotes_received,
    ua.bronze_badges,
    ua.silver_badges,
    ua.gold_badges,
    case when ua.answers > 0 then round(ua.upvotes_received::numeric / ua.answers, 4) else null end as upvotes_per_answer,
    case when ua.questions > 0 then round(ua.question_views::numeric / ua.questions, 4) else null end as avg_views_per_question,
    case when ua.total_posts > 0 then round(ua.post_score::numeric / ua.total_posts, 4) else null end as avg_score_per_post,
    rank() over (partition by au.rep_tier order by ua.post_score desc nulls last, ua.total_posts desc, au.user_id) as score_rank_in_tier,
    dense_rank() over (order by ua.post_score desc nulls last) as global_dense_rank,
    row_number() over (order by ua.total_posts desc nulls last, ua.post_score desc, au.user_id) as activity_rownum
  from active_users au
  join user_activity ua on ua.user_id = au.user_id
),
-- compute post-level metrics including closure and accepted answers
post_metrics as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.acceptedanswerid,
    p.closeddate,
    exists (
      select 1
      from posthistory ph
      where ph.postid = p.id
        and ph.posthistorytypeid = 10
    ) as has_close_votes,
    exists (
      select 1
      from postlinks pl
      where pl.postid = p.id
        and pl.linktypeid = 3
    ) as marked_duplicate,
    case
      when p.tags is null then 0
      else cardinality(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))
    end as tag_count,
    -- estimated reading effort by body length buckets
    case
      when p.body is null then 0
      else greatest(1, length(p.body) / 500)
    end as reading_blocks
  from posts p
  where p.posttypeid in (1,2)
),
-- per-user post windows for recency and streaks
user_post_windows as (
  select
    pm.owneruserid as user_id,
    pm.post_id,
    pm.posttypeid,
    pm.creationdate,
    pm.score,
    pm.viewcount,
    pm.answercount,
    pm.acceptedanswerid,
    pm.closeddate,
    pm.has_close_votes,
    pm.marked_duplicate,
    pm.tag_count,
    pm.reading_blocks,
    lag(pm.creationdate) over (partition by pm.owneruserid order by pm.creationdate) as prev_post_date,
    lead(pm.creationdate) over (partition by pm.owneruserid order by pm.creationdate) as next_post_date,
    count(*) over (partition by pm.owneruserid) as posts_by_user,
    sum(case when pm.score > 0 then 1 else 0 end) over (partition by pm.owneruserid) as positive_posts_by_user
  from post_metrics pm
),
-- derive streaks and volatility
user_post_analytics as (
  select
    upw.*,
    case
      when prev_post_date is null then null
      else extract(epoch from (upw.creationdate - prev_post_date)) / 3600.0
    end as hours_since_prev,
    case
      when next_post_date is null then null
      else extract(epoch from (next_post_date - upw.creationdate)) / 3600.0
    end as hours_until_next,
    case when upw.posttypeid = 1 and upw.acceptedanswerid is not null then 1 else 0 end as question_with_accepted,
    case when upw.closeddate is not null then 1 else 0 end as was_closed,
    case when upw.marked_duplicate then 1 else 0 end as was_duplicate
  from user_post_windows upw
),
-- summarize per-user advanced metrics with correlated subqueries and null logic
user_advanced as (
  select
    u.user_id,
    coalesce(avg(upa.hours_since_prev) filter (where upa.hours_since_prev is not null), 0) as avg_hours_between_posts,
    coalesce(stddev_pop(upa.score::numeric), 0) as score_volatility,
    sum(upa.question_with_accepted) as accepted_questions,
    sum(upa.was_closed) as closed_posts,
    sum(upa.was_duplicate) as duplicate_posts,
    max(upa.viewcount) as max_views,
    min(nullif(upa.viewcount, 0)) as min_nonzero_views,
    coalesce(avg(case when upa.tag_count > 0 then upa.score::numeric / upa.tag_count end), 0) as avg_score_per_tag,
    coalesce(sum(case when upa.reading_blocks >= 3 and upa.score >= 5 then 1 else 0 end), 0) as high_effort_successes,
    -- correlated: favorite votes to user's posts
    coalesce((
      select count(*)
      from votes v
      join posts p on p.id = v.postid
      where v.votetypeid = 5
        and p.owneruserid = u.user_id
    ), 0) as favorites_received,
    -- correlated: edits applied on user's posts
    coalesce((
      select count(*)
      from posthistory ph
      join posts p on p.id = ph.postid
      where ph.posthistorytypeid in (24,5,4,6)
        and p.owneruserid = u.user_id
    ), 0) as edits_applied
  from user_post_analytics upa
  right join ranked_users u on u.user_id = upa.user_id
  group by u.user_id
),
-- combine and compute composite scores with null-safe math
final_scores as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.rep_tier,
    r.total_posts,
    r.questions,
    r.answers,
    r.post_score,
    r.question_views,
    r.comments_made,
    r.upvotes_received,
    r.downvotes_received,
    r.bronze_badges,
    r.silver_badges,
    r.gold_badges,
    r.upvotes_per_answer,
    r.avg_views_per_question,
    r.avg_score_per_post,
    r.score_rank_in_tier,
    r.global_dense_rank,
    r.activity_rownum,
    ua.avg_hours_between_posts,
    ua.score_volatility,
    ua.accepted_questions,
    ua.closed_posts,
    ua.duplicate_posts,
    ua.max_views,
    ua.min_nonzero_views,
    ua.avg_score_per_tag,
    ua.high_effort_successes,
    ua.favorites_received,
    ua.edits_applied,
    -- composite score with weighted components and NULL protection
    round((
      coalesce(r.post_score, 0) * 1.0 +
      coalesce(r.upvotes_received, 0) * 2.0 -
      coalesce(r.downvotes_received, 0) * 1.5 +
      coalesce(r.answers, 0) * 0.75 +
      coalesce(r.questions, 0) * 0.5 +
      coalesce(ua.favorites_received, 0) * 1.25 +
      coalesce(ua.high_effort_successes, 0) * 3.0 +
      coalesce(r.gold_badges, 0) * 5.0 +
      coalesce(r.silver_badges, 0) * 2.5 +
      coalesce(r.bronze_badges, 0) * 1.0 -
      coalesce(ua.closed_posts, 0) * 2.0 -
      coalesce(ua.duplicate_posts, 0) * 1.0 -
      least(coalesce(ua.avg_hours_between_posts, 0)::numeric, 720)::numeric * 0.05
    )::numeric, 3) as composite_score
  from ranked_users r
  join user_advanced ua on ua.user_id = r.user_id
),
-- identify users with both high composite and anomaly patterns via set operators
top_candidates as (
  select * from final_scores
  where composite_score >= (
    select percentile_disc(0.95) within group (order by composite_score)
    from final_scores
  )
  union
  select fs.*
  from final_scores fs
  where fs.score_volatility >= (
    select percentile_disc(0.99) within group (order by score_volatility)
    from final_scores
  )
),
-- build text summary per user using string expressions and null handling
user_summaries as (
  select
    t.user_id,
    ('User "' || coalesce(t.displayname, '(unknown)') || '" [' || t.rep_tier || ']') ||
    ' Posts=' || coalesce(t.total_posts::text, '0') ||
    ', Q=' || coalesce(t.questions::text, '0') ||
    ', A=' || coalesce(t.answers::text, '0') ||
    ', Score=' || coalesce(t.post_score::text, '0') ||
    ', Views/Question=' || coalesce(to_char(t.avg_views_per_question, 'FM999999990.0000'), 'n/a') ||
    ', Up/Ans=' || coalesce(to_char(t.upvotes_per_answer, 'FM999999990.0000'), 'n/a') ||
    ', Badges(G/S/B)=' || t.gold_badges || '/' || t.silver_badges || '/' || t.bronze_badges ||
    ', Closed=' || t.closed_posts || ', Dups=' || t.duplicate_posts ||
    ', Vol=' || coalesce(to_char(t.score_volatility, 'FM999999990.0000'), '0') ||
    ', Comp=' || coalesce(to_char(t.composite_score, 'FM999999990.000'), '0')
    as summary
  from top_candidates t
),
-- tier-wise aggregates for context
tier_stats as (
  select
    rep_tier,
    count(*) as users_in_tier,
    avg(composite_score) as avg_composite_tier,
    max(composite_score) as max_composite_tier,
    min(composite_score) as min_composite_tier
  from final_scores
  group by rep_tier
)
select
  fs.user_id,
  fs.displayname,
  fs.rep_tier,
  fs.reputation,
  fs.total_posts,
  fs.questions,
  fs.answers,
  fs.post_score,
  fs.avg_score_per_post,
  fs.avg_views_per_question,
  fs.upvotes_per_answer,
  fs.upvotes_received,
  fs.downvotes_received,
  fs.gold_badges,
  fs.silver_badges,
  fs.bronze_badges,
  fs.accepted_questions,
  fs.closed_posts,
  fs.duplicate_posts,
  fs.high_effort_successes,
  fs.favorites_received,
  fs.edits_applied,
  fs.score_volatility,
  fs.avg_hours_between_posts,
  fs.composite_score,
  fs.score_rank_in_tier,
  fs.global_dense_rank,
  us.summary,
  ts.users_in_tier,
  ts.avg_composite_tier,
  ts.max_composite_tier,
  ts.min_composite_tier
from top_candidates fs
left join user_summaries us on us.user_id = fs.user_id
left join tier_stats ts on ts.rep_tier = fs.rep_tier
where (
  -- complicated predicate combining multiple conditions and null logic
  (fs.answers > fs.questions and coalesce(fs.upvotes_per_answer, 0) >= 1.0)
  or (fs.questions >= 10 and coalesce(fs.avg_views_per_question, 0) >= 1000)
  or (fs.composite_score >= ts.avg_composite_tier + greatest(10, coalesce(ts.avg_composite_tier, 0) * 0.25))
)
order by fs.composite_score desc nulls last, fs.score_volatility desc nulls last, fs.user_id
limit 200;