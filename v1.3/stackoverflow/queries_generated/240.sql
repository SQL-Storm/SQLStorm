-- {"query": "240.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3496} 
with
-- basic per-user post aggregates
user_posts as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    count(p.id) filter (where p.posttypeid in (1,2)) as total_posts,
    count(p.id) filter (where p.posttypeid = 1) as question_count,
    count(p.id) filter (where p.posttypeid = 2) as answer_count,
    avg(p.score) filter (where p.posttypeid in (1,2)) as avg_post_score,
    max(p.creationdate) filter (where p.posttypeid in (1,2)) as last_post_date,
    min(p.creationdate) filter (where p.posttypeid in (1,2)) as first_post_date,
    greatest(
      0,
      extract(epoch from (coalesce(max(p.creationdate), u.creationdate) - coalesce(min(p.creationdate), u.creationdate))) / (60*60*24)
    )::int as active_days
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate
),

-- unnest tags from question posts and count per user and tag
user_tag_usage as (
  select
    p.owneruserid as user_id,
    tagname,
    count(*) as tag_count
  from posts p
  -- only questions have Tags; guard nulls
  cross join lateral (
    select regexp_split_to_table(substring(p.tags, 2, char_length(p.tags)-2), '><') as tagname
  ) t
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
  group by p.owneruserid, tagname
),

-- top tag per user (ties broken by tagname)
top_tag_per_user as (
  select user_id, tagname as top_tag, tag_count
  from (
    select *,
      row_number() over (partition by user_id order by tag_count desc, tagname) rn
    from user_tag_usage
  ) x
  where rn = 1
),

-- votes summary for posts owned by each user
user_votes as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_received,
    sum(case when v.votetypeid = 1 then 1 else 0 end) as accepts_received
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),

-- badges per user with tag-based breakdown
badge_summary as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_based_badges
  from badges b
  group by b.userid
),

-- per-user accepted-answers authored (answers that were accepted)
user_accepted_answers as (
  select a.owneruserid as user_id, count(*) as accepted_answers_count
  from posts a
  join posts q on q.acceptedanswerid = a.id
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),

-- average time to first answer for questions the user asked (in hours)
user_avg_time_to_first_answer as (
  select
    q.owneruserid as user_id,
    avg(extract(epoch from (first_answer) - extract(epoch from q.creationdate))/3600.0) filter (where first_answer is not null) as avg_hours_to_first_answer
  from posts q
  left join lateral (
    select min(a.creationdate) as first_answer
    from posts a
    where a.parentid = q.id and a.posttypeid = 2 and a.creationdate > q.creationdate
  ) fa on true
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),

-- highlight a set of posts: top questions and top answers by score, unioned, excluding low-view posts
high_impact_posts as (
  (select p.id, p.posttypeid, p.owneruserid, p.title, p.score, p.viewcount, p.creationdate, 'top_question' as kind
   from posts p
   where p.posttypeid = 1
   order by p.score desc nulls last, p.viewcount desc nulls last
   limit 100)
  union
  (select p.id, p.posttypeid, p.owneruserid, substring(coalesce(p.body, '') from 1 for 200) as title, p.score, p.viewcount, p.creationdate, 'top_answer' as kind
   from posts p
   where p.posttypeid = 2
   order by p.score desc nulls last
   limit 100)
),

-- sample comments: latest comment for each high impact post (lateral correlated subquery)
post_latest_comment as (
  select hip.*, c.id as comment_id, c.text as latest_comment_text, c.creationdate as comment_date
  from high_impact_posts hip
  left join lateral (
    select * from comments c2
    where c2.postid = hip.id
    order by c2.creationdate desc
    limit 1
  ) c on true
),

-- compute global thresholds for influence (percentiles)
user_influence_ranks as (
  select
    up.user_id,
    up.total_posts,
    uv.upvotes_received,
    uv.downvotes_received,
    rank() over (order by coalesce(uv.upvotes_received,0) desc) as upvote_rank,
    ntile(10) over (order by coalesce(uv.upvotes_received,0)) as upvote_ntile,
    percentile_cont(0.75) within group (order by coalesce(uv.upvotes_received,0)) over () as p75_upvotes
  from user_posts up
  left join user_votes uv on uv.user_id = up.user_id
),

-- identify high-influence users using correlated subquery and NULL logic
high_influence_users as (
  select uir.user_id
  from user_influence_ranks uir
  where
    coalesce(uir.upvote_ntile,0) > 7
    and coalesce(uir.upvotes_received,0) >= coalesce(uir.p75_upvotes,0)
    and exists (
      select 1 from user_posts up2 where up2.user_id = uir.user_id and up2.active_days > 30 and up2.total_posts > 5
    )
),

-- assemble final user-centric view with many calculated fields
final_users as (
  select
    up.user_id,
    up.displayname,
    up.reputation,
    up.total_posts,
    up.question_count,
    up.answer_count,
    coalesce(uv.upvotes_received,0) as upvotes_received,
    coalesce(uv.downvotes_received,0) as downvotes_received,
    coalesce(uv.favorites_received,0) as favorites_received,
    coalesce(ua.accepted_answers_count,0) as accepted_answers_count,
    coalesce(bs.badge_count,0) as badge_count,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(tt.top_tag, '(none)') as top_tag,
    coalesce(ut.avg_hours_to_first_answer, -1) as avg_hours_to_first_answer,
    case
      when coalesce(uv.downvotes_received,0) = 0 then nullif(coalesce(uv.upvotes_received,0),0)
      else round( (coalesce(uv.upvotes_received,0)::numeric / nullif(coalesce(uv.downvotes_received,0),0))::numeric, 3)
    end as up_down_ratio,
    -- engagement score with logs, active_days, badges and views (synthetic heavy calculation)
    round(
      (
        log(1 + coalesce(uv.upvotes_received,0))
        + sqrt(coalesce(bs.badge_count,0) + 1)
        + (case when coalesce(up.question_count,0) > 0 then 1 else 0 end) * 0.5
        + (case when up.active_days > 0 then log(up.active_days + 1) else 0 end)
      ) * greatest(1, (coalesce(uv.favorites_received,0) + 1)/2.0)
    , 4) as engagement_score,
    -- indicator flags
    case when hi.user_id is not null then true else false end as is_high_influence,
    -- create a synthetic "bio_snippet" built from name, top_tag and badge counts
    (coalesce(up.displayname,'<anon>') || ' | top tag: ' || coalesce(tt.top_tag,'(none)') || ' | badges: ' || coalesce(bs.badge_count,0)::text) as bio_snippet
  from user_posts up
  left join user_votes uv on uv.user_id = up.user_id
  left join badge_summary bs on bs.user_id = up.user_id
  left join top_tag_per_user tt on tt.user_id = up.user_id
  left join user_accepted_answers ua on ua.user_id = up.user_id
  left join user_avg_time_to_first_answer ut on ut.user_id = up.user_id
  left join high_influence_users hi on hi.user_id = up.user_id
)

-- final selection with window functions, filtering, string and null logic, and a small sample of high impact posts via lateral join
select
  fu.user_id,
  fu.displayname,
  fu.reputation,
  fu.total_posts,
  fu.question_count,
  fu.answer_count,
  fu.upvotes_received,
  fu.downvotes_received,
  fu.up_down_ratio,
  fu.accepted_answers_count,
  fu.badge_count,
  fu.gold_badges,
  coalesce(fu.top_tag,'(none)') as top_tag,
  fu.avg_hours_to_first_answer,
  fu.engagement_score,
  fu.is_high_influence,
  fu.bio_snippet,
  -- rank users by engagement_score within reputation deciles
  rank() over (partition by ntile(5) over (order by fu.reputation) order by fu.engagement_score desc) as rank_within_repdentile,
  -- a correlated sample of one recent high impact post for this user
  hip.id as sample_post_id,
  hip.kind as sample_post_kind,
  hip.title as sample_post_title,
  hip.score as sample_post_score,
  hip.viewcount as sample_post_views,
  hip.latest_comment_text
from final_users fu
left join lateral (
  select plp.id, plp.kind, plp.title, plp.score, plp.viewcount, plc.latest_comment_text
  from high_impact_posts plp
  left join post_latest_comment plc on plc.id = plp.id
  where plp.owneruserid = fu.user_id
  order by plp.score desc nulls last, plp.viewcount desc nulls last
  limit 1
) hip on true
where fu.total_posts > 0
order by fu.engagement_score desc nulls last, fu.reputation desc nulls last
limit 250;